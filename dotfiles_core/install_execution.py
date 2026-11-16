"""Installation item scheduling, snapshots and failure blocking.

Native callbacks own command execution, atomic report publication and live
output. A successful installation command is final: there is no post-install
presence verification.
"""
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
import time
from pathlib import Path

from dotfiles_core.contracts import Contract, ContractError, install_result_row
from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.execution_rules import execution_policy, execution_result
from dotfiles_core.install_planning import Item


@dataclass(frozen=True)
class InstallationResult:
    exit_code: int
    rows: tuple[str, ...]


def emit_line(text: str) -> None:
    print(text, flush=True)


def execute(items: Sequence[Mapping[str, str]], *, dry: bool, resume: bool,
            install: Callable[[Item], None], observe: Callable[[Item], Item],
            publish: Callable[[str], None] | None = None,
            emit: Callable[[str], None] = emit_line,
            clock: Callable[[], float] = time.monotonic,
            style: str = 'unix', policy_path: str = '') -> InstallationResult:
    plan_schema = Contract.load('install-plan')
    result_schema = Contract.load('install-result')
    # Native PowerShell callers may omit optional fields; the external contract
    # has always serialized those as empty strings.
    items = plan_schema.read(plan_schema.write(items))
    for item in items:
        if str(item.get('schema_version')) != plan_schema.version:
            raise ContractError('Unsupported install plan record version')
        if item.get('action') not in ('install', 'upgrade', 'skip'):
            raise ContractError('Invalid install action')
    if policy_path:
        execution_policy('*', 'install', Path(policy_path))
    else:
        execution_policy('*', 'install')
    completed = []
    stopped = 0

    def snapshot(extra: str | None = None) -> None:
        if publish is not None:
            publish(result_schema.from_rows('\n'.join([*completed, extra] if extra else completed)))

    for original in items:
        item = dict(original)
        started = clock()
        reason = item['reason']
        observed = True
        failure = None
        if not stopped and resume:
            snapshot(install_result_row(item, 'running', '0', 'checking-current-state', False))
            try:
                refreshed = observe(item)
                if refreshed.get('id') != original['id']:
                    raise AdapterError('Installation observation identity mismatch', 65)
                item = refreshed
                reason = item['reason']
            except (AdapterError, ProtocolError) as exc:
                failure, observed = exc, False
        if stopped:
            status, reason, observed = 'blocked', 'previous-failure', False
        elif failure is None and item['action'] == 'skip':
            status = 'skipped'
        else:
            try:
                if failure is not None:
                    raise failure
                snapshot(install_result_row(item, 'running', '0', reason))
                emit(f"Install {item['id']}: {item['action']} ({item['method']}, source={item['source_origin']})")
                install(item)
                status = execution_result(0, dry)['Status']
            except (AdapterError, ProtocolError) as exc:
                stopped = getattr(exc, 'exit_code', 65)
                outcome = execution_result(stopped, dry)
                status, reason = outcome['Status'], outcome['Reason']
                if style == 'windows':
                    emit('WARNING: ' + str(exc))
        elapsed = str(max(0, int(clock() - started)))
        row = install_result_row(item, status, elapsed, reason, observed)
        completed.append(row)
        snapshot()
        if style == 'windows':
            emit('Result ' + row)
        else:
            emit(f"Result {item['id']}: {status} ({elapsed}s; {reason})")
    snapshot()
    emit('Installation item summary:\n' + '\n'.join(completed))
    return InstallationResult(stopped, tuple(completed))
