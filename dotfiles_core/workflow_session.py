"""Workflow session lifetime and stage scheduling.

Native operations retain atomic publication and the complete command/logging
boundary. The caller holds its deployment lease for this entire operation.
"""
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Protocol
import json
import re
import shutil
import tempfile
import time

from dotfiles_core.contracts import Contract, ContractError
from dotfiles_core.execution_rules import execution_result
from dotfiles_core.stage_results import initial_stage, finish_stage, read_stage
from dotfiles_core.workflow_review import request_document


@dataclass(frozen=True)
class Stage:
    identity: str
    enabled: bool
    reason: str
    action: str


@dataclass(frozen=True)
class Session:
    identity: str
    path: Path
    profile: str
    platform: str
    style: str
    dry: bool
    mirrors: bool
    stages: tuple[Stage, ...]
    results: str = ''
    parent: str = ''
    # Unix context lifetime is owned by the entry point; Windows has no such
    # directory and creates/removes its ephemeral session here.
    context_directory: Path | None = None

    @property
    def persistent(self) -> bool:
        return not self.dry or bool(self.results)


@dataclass(frozen=True)
class StageExecution:
    exit_code: int
    reason: str = ''


class Operations(Protocol):
    def publish(self, path: Path, text: str, mode: str = 'replace') -> None: ...

    def execute(self, action: str, report: Path, metadata: Path, log: Path) -> StageExecution: ...


@dataclass(frozen=True)
class SessionResult:
    exit_code: int
    rows: tuple[dict, ...]
    summary: str


def snapshot(rows: list[dict], style: str) -> str:
    if style == 'windows':
        return json.dumps(rows, ensure_ascii=False, indent=2) + '\n'
    if style != 'unix':
        raise ContractError('Unknown workflow summary style')
    schema = Contract.load('workflow-summary')
    return '|'.join(schema.fields) + '\n' + ''.join(schema.row(row) + '\n' for row in rows)


def run(session: Session, operations: Operations, *,
        emit: Callable[[str], None] = print,
        clock: Callable[[], float] = time.monotonic) -> SessionResult:
    """Execute a preflighted current selection; previous success is no skip rule."""
    if session.style not in ('unix', 'windows'):
        raise ContractError('Unknown workflow session style')
    seen = set()
    for stage in session.stages:
        if (not re.fullmatch('[a-z][a-z0-9-]*', stage.identity) or stage.identity in seen
                or type(stage.enabled) is not bool):
            raise ContractError('Invalid workflow stage selection')
        seen.add(stage.identity)
    if session.style == 'unix':
        if session.context_directory is None:
            raise ContractError('Missing Unix workflow context directory')
        directory = session.context_directory / 'runtime'
        directory.mkdir()
        if session.persistent:
            session.path.parent.mkdir(parents=True, exist_ok=True)
            session.path.mkdir()
            directory = session.path
    elif session.persistent:
        session.path.mkdir(parents=True)
        directory = session.path
    else:
        directory = Path(tempfile.mkdtemp(prefix='dotfiles-workflow-'))
    try:
        return _stages(session, directory, operations, emit, clock)
    finally:
        if session.style == 'windows' and not session.persistent:
            shutil.rmtree(directory)


def _stages(session: Session, directory: Path, operations: Operations,
            emit: Callable[[str], None], clock: Callable[[], float]) -> SessionResult:
    selected = [stage.identity for stage in session.stages if stage.enabled]
    document = request_document(session.platform, session.profile, str(int(session.mirrors)),
                                selected, session.parent, str(int(session.dry)))
    if document is not None:
        operations.publish(directory / 'request.tsv', document + '\n')
    suffix = 'tsv' if session.style == 'unix' else 'json'
    summary = directory / ('workflow.' + suffix)
    rows: list[dict] = []
    initial = snapshot(rows, session.style)
    if session.style == 'unix':
        operations.publish(summary, initial)
    if session.results:
        operations.publish(Path(session.results), initial, 'create')
    if session.style == 'unix':
        (directory / 'events.tsv').write_text(initial, encoding='utf-8')
        (directory / 'completed.tsv').write_text(initial, encoding='utf-8')
    emit(f'Workflow session: {session.identity}')
    stopped = 0
    retry = ''

    def publish(current: list[dict]) -> None:
        if session.persistent or session.style == 'unix':
            text = snapshot(current, session.style)
            operations.publish(summary, text)
            if session.results:
                operations.publish(Path(session.results), text)

    def append(name: str, row: dict) -> None:
        with (directory / name).open('a', encoding='utf-8') as stream:
            stream.write(Contract.load('workflow-summary').row(row) + '\n')

    for stage in session.stages:
        started = clock()
        row = dict(schema_version=1, session=session.identity, profile=session.profile,
                   stage=stage.identity, status='skipped', exit_code=0, elapsed_seconds=0,
                   log='', report='', recovery_journal='', child_report='',
                   reason=stage.reason if session.style == 'unix' or not stage.enabled else '',
                   retry_stage=retry)
        if not stage.enabled:
            pass
        elif stopped:
            row.update(status='blocked', reason='previous-stage-failed')
        else:
            log = directory / (stage.identity + '.log')
            report = directory / (stage.identity + '.tsv')
            metadata = directory / (stage.identity + '.result')
            running = {**row, 'status': 'running', 'reason': 'started',
                       'log': str(log), 'report': str(report), 'retry_stage': stage.identity}
            if session.style == 'unix':
                append('events.tsv', running)
            publish([*rows, running])
            operations.publish(metadata, initial_stage(stage.identity, str(report)) + '\n', 'create')
            executed = operations.execute(stage.action, report, metadata, log)
            code = executed.exit_code
            reason = executed.reason
            try:
                exists = report.is_file() if session.style == 'unix' else report.exists()
                document = finish_stage(metadata.read_text(encoding='utf-8-sig'), code,
                                        session.dry, str(report), exists)
                operations.publish(metadata, document + '\n')
                artifacts = read_stage(document)
                for key in ('child_report', 'recovery_journal'):
                    row[key] = ','.join(item['value'] for item in artifacts if item['key'] == key)
            except (ContractError, OSError, UnicodeError):
                code = 65
                reason = 'invalid-stage-result'
                emit(f'error: invalid stage result: {metadata}')
            outcome = execution_result(code, session.dry)
            row.update(status=outcome['Status'], exit_code=code)
            if code:
                stopped = code
                retry = stage.identity
                row['reason'] = reason if session.style == 'windows' and reason else outcome['Reason']
            if session.persistent:
                row['log'] = str(log)
                row['report'] = str(report) if (report.is_file() if session.style == 'unix' else report.exists()) else ''
        elapsed = max(0.0, clock() - started)
        row.update(elapsed_seconds=int(elapsed) if session.style == 'unix' else round(elapsed), retry_stage=retry)
        rows.append(row)
        if session.style == 'unix':
            append('completed.tsv', row)
        publish(rows)
        if session.style == 'unix':
            append('events.tsv', row)
        emit(f'Stage {stage.identity}: {row["status"]}')
    if session.persistent:
        emit(f'Workflow report: {summary}')
    return SessionResult(stopped, tuple(rows), str(summary) if session.persistent else '')
