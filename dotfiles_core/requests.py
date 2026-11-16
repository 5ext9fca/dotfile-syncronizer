"""Private request/result files for native compatibility adapters."""
from pathlib import Path
import os
import zipfile

from dotfiles_core.errors import CoreError, ProtocolError, AdapterError
from dotfiles_core.protocol import Request, Result, write_json, exit_codes_match


def prepare(arguments: Path, request_path: Path) -> None:
    """Encode Bash's literal NUL-framed values without shell JSON escaping."""
    values = arguments.read_bytes().decode('utf-8').split('\0')
    if not values or values.pop() != '' or len(values) % 2 != 1:
        raise ProtocolError('Malformed native request arguments')
    operation, *pairs = values
    context = {}
    for index in range(0, len(pairs), 2):
        key, value = pairs[index:index + 2]
        if key in context:
            raise ProtocolError('Duplicate native request argument')
        context[key] = value
    write_json(request_path, Request(operation, context).document())


def run(request_path: Path, result_path: Path) -> int:
    request = Request.read(request_path)
    from dotfiles_core.contracts import OPERATIONS, request as contract_request
    from dotfiles_core.stage_results import OPERATIONS as STAGE_OPERATIONS, request as stage_request
    from dotfiles_core.workflow_review import OPERATIONS as REVIEW_OPERATIONS, request as review_request
    from dotfiles_core.apply_rules import OPERATIONS as APPLY_OPERATIONS, request as apply_request
    from dotfiles_core.install_planning import OPERATIONS as INSTALL_OPERATIONS, request as install_request
    from dotfiles_core.native_installation import OPERATIONS as NATIVE_INSTALL_OPERATIONS, request as native_install_request
    from dotfiles_core.native_apply import OPERATIONS as NATIVE_APPLY_OPERATIONS, request as native_apply_request
    from dotfiles_core.mirror_planning import OPERATIONS as MIRROR_OPERATIONS, request as mirror_request
    from dotfiles_core.native_workflow import OPERATIONS as SESSION_OPERATIONS, request as session_request
    from dotfiles_core.native_preflight import OPERATIONS as PREFLIGHT_OPERATIONS, request as preflight_request
    from dotfiles_core.workflow_packages import OPERATIONS as PACKAGE_OPERATIONS, request as package_request
    from dotfiles_core.apply_execution import OPERATIONS as APPLY_EXEC_OPERATIONS, request as apply_execute_request
    from dotfiles_core.apply_entry import OPERATIONS as APPLY_ENTRY_OPERATIONS, request as apply_entry_request
    from dotfiles_core.workflow_shell import OPERATIONS as SHELL_OPERATIONS, request as shell_request
    from dotfiles_core.plan_explain import OPERATIONS as EXPLAIN_OPERATIONS, request as explain_request
    from dotfiles_core.snapshot_entry import OPERATIONS as SNAPSHOT_OPERATIONS, request as snapshot_request
    try:
        if request.operation in SNAPSHOT_OPERATIONS:
            value, lines = snapshot_request(request.operation, request.context)
        elif request.operation in EXPLAIN_OPERATIONS:
            value, lines = explain_request(request.operation, request.context)
        elif request.operation in SHELL_OPERATIONS:
            value, lines = shell_request(request.operation, request.context)
        elif request.operation in APPLY_ENTRY_OPERATIONS:
            value, lines = apply_entry_request(request.operation, request.context)
        elif request.operation in APPLY_EXEC_OPERATIONS:
            value, lines = apply_execute_request(request.operation, request.context)
        elif request.operation in OPERATIONS:
            value, lines = contract_request(request.operation, request.context)
        elif request.operation in STAGE_OPERATIONS:
            value, lines = stage_request(request.operation, request.context)
        elif request.operation in REVIEW_OPERATIONS:
            value, lines = review_request(request.operation, request.context)
        elif request.operation in APPLY_OPERATIONS:
            value, lines = apply_request(request.operation, request.context)
        elif request.operation in INSTALL_OPERATIONS:
            value, lines = install_request(request.operation, request.context)
        elif request.operation in NATIVE_INSTALL_OPERATIONS:
            value, lines = native_install_request(request.operation, request.context)
        elif request.operation in NATIVE_APPLY_OPERATIONS:
            value, lines = native_apply_request(request.operation, request.context)
        elif request.operation in MIRROR_OPERATIONS:
            value, lines = mirror_request(request.operation, request.context)
        elif request.operation in SESSION_OPERATIONS:
            value, lines = session_request(request.operation, request.context)
        elif request.operation in PREFLIGHT_OPERATIONS:
            value, lines = preflight_request(request.operation, request.context)
        elif request.operation in PACKAGE_OPERATIONS:
            value, lines = package_request(request.operation, request.context)
        else:
            raise ProtocolError(f'Unsupported core request: {request.operation}')
        result = Result(request.operation, 0, {'value': value, 'lines': lines})
    except (CoreError, OSError, UnicodeError, KeyError, TypeError, ValueError, zipfile.BadZipFile, NotImplementedError) as exc:
        result = Result(request.operation, getattr(exc, 'exit_code', 1), {'error': str(exc)})
    write_json(result_path, result.document())
    return result.exit_code


def read_result(path: Path, operation: str, code: int) -> list[str]:
    result = Result.read(path, operation)
    if not exit_codes_match(code, result.exit_code, windows=os.name == 'nt'):
        raise ProtocolError('Core process and result exit codes disagree')
    if code:
        raise AdapterError(result.data.get('error', 'Core request failed'), result.exit_code)
    if set(result.data) != {'value', 'lines'}:
        raise ProtocolError('Malformed core result data')
    lines = result.data.get('lines')
    if not isinstance(lines, list) or not all(isinstance(line, str) for line in lines):
        raise ProtocolError('Malformed core result lines')
    return lines
