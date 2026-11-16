"""Ephemeral UTF-8 JSON exchange with explicitly registered platform operations.

The platform adapter owns native command policy, timeouts and cancellation. This
transport inherits stdin/stdout/stderr and does not turn requests into replayable
plans. A zero process exit without a valid matching result is never success.
"""

import json
import os
import subprocess
import tempfile
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from dotfiles_core.errors import AdapterError, ProtocolError

PROTOCOL_VERSION = 1


def exit_codes_match(process_code: int, reported_code: int, *, windows: bool = False) -> bool:
    # Win32 process status is an unsigned DWORD; PowerShell/.NET exposes its
    # signed Int32 representation. Keep the native report's original code.
    if windows:
        return (-0x80000000 <= process_code <= 0xffffffff
                and -0x80000000 <= reported_code <= 0xffffffff
                and (process_code & 0xffffffff) == (reported_code & 0xffffffff))
    return process_code == reported_code


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ProtocolError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def _invalid_constant(value: str) -> None:
    raise ProtocolError(f"Invalid JSON constant: {value}")


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"),
                           object_pairs_hook=_unique_object,
                           parse_constant=_invalid_constant)
    except (OSError, UnicodeError, ValueError) as exc:
        raise ProtocolError(f"Cannot read adapter document {path.name}: {exc}") from exc
    if not isinstance(value, dict):
        raise ProtocolError("Adapter document must be a JSON object")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    try:
        path.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False) + "\n",
                        encoding="utf-8")
    except (OSError, UnicodeError, ValueError, TypeError) as exc:
        raise ProtocolError(f"Cannot write adapter document {path.name}: {exc}") from exc


def _envelope(value: dict[str, Any], fields: set[str]) -> None:
    if set(value) != fields:
        raise ProtocolError("Unknown or missing adapter document fields")
    if type(value["protocol_version"]) is not int or value["protocol_version"] != PROTOCOL_VERSION:
        raise ProtocolError("Unsupported adapter protocol version")
    if not isinstance(value["operation"], str) or not value["operation"]:
        raise ProtocolError("Missing adapter operation")


@dataclass(frozen=True)
class Request:
    operation: str
    context: dict[str, Any]

    def document(self) -> dict[str, Any]:
        return {"protocol_version": PROTOCOL_VERSION, "operation": self.operation,
                "context": self.context}

    @classmethod
    def read(cls, path: Path) -> Request:
        value = read_json(path)
        _envelope(value, {"protocol_version", "operation", "context"})
        if not isinstance(value["context"], dict):
            raise ProtocolError("Adapter context must be an object")
        return cls(value["operation"], value["context"])


@dataclass(frozen=True)
class Result:
    operation: str
    exit_code: int
    data: dict[str, Any]

    def document(self) -> dict[str, Any]:
        return {"protocol_version": PROTOCOL_VERSION, "operation": self.operation,
                "exit_code": self.exit_code, "data": self.data}

    @classmethod
    def read(cls, path: Path, operation: str) -> Result:
        value = read_json(path)
        _envelope(value, {"protocol_version", "operation", "exit_code", "data"})
        if value["operation"] != operation:
            raise ProtocolError("Adapter result operation does not match request")
        if type(value["exit_code"]) is not int or not isinstance(value["data"], dict):
            raise ProtocolError("Invalid adapter result")
        return cls(operation, value["exit_code"], value["data"])


def dispatch(request_path: Path, result_path: Path,
             operations: Mapping[str, Callable[[dict[str, Any]], Result]]) -> int:
    request = Request.read(request_path)
    handler = operations.get(request.operation)
    if handler is None:
        raise ProtocolError(f"Unsupported adapter operation: {request.operation}")
    result = handler(request.context)
    if result.operation != request.operation:
        raise ProtocolError("Handler returned a result for another operation")
    write_json(result_path, result.document())
    return result.exit_code


class Adapter:
    def __init__(self, operations: Mapping[str, Sequence[str]], *, scratch: Path | None = None):
        self.operations = {name: tuple(command) for name, command in operations.items()}
        self.scratch = scratch

    def invoke(self, operation: str, context: dict[str, Any]) -> Result:
        command = self.operations.get(operation)
        if not command or not all(isinstance(arg, str) and arg for arg in command):
            raise ProtocolError(f"Unsupported adapter operation: {operation}")
        # mkdtemp creates a private directory; its scope also bounds cleanup.
        with tempfile.TemporaryDirectory(prefix="dotfiles-adapter-", dir=self.scratch) as directory:
            request_path = Path(directory) / "request.json"
            result_path = Path(directory) / "result.json"
            write_json(request_path, Request(operation, context).document())
            try:
                process = subprocess.run([*command, str(request_path), str(result_path)], check=False)
            except OSError as exc:
                raise AdapterError(f"Cannot start adapter: {exc}", 127) from exc
            result = Result.read(result_path, operation)
            if not exit_codes_match(process.returncode, result.exit_code, windows=os.name == 'nt'):
                raise ProtocolError("Adapter process and result exit codes disagree")
            if process.returncode:
                raise AdapterError(f"Adapter operation failed: {operation}", result.exit_code)
            return result
