"""Pure installation/execution policy driven by the existing schema registries."""
from dataclasses import dataclass
from pathlib import Path
import re

from dotfiles_core.errors import CoreError
from dotfiles_core.install_config import ROOT, rows


class PolicyError(CoreError):
    pass


@dataclass(frozen=True)
class ExecutionPolicy:
    TimeoutSeconds: int
    SuccessCodes: list[int]

    def text(self) -> str:
        return f'{self.TimeoutSeconds}|' + ','.join(map(str, self.SuccessCodes))


def execution_policy(method: str, operation: str, path: Path = ROOT / 'install/schema/execution.tsv') -> ExecutionPolicy:
    methods = {row[0] for row in rows(ROOT / 'install/schema/methods.tsv')}
    policies = {}
    operations = {'probe', 'install', 'download', 'modify'}
    for cells in rows(path):
        if len(cells) != 4:
            raise PolicyError('Invalid installation execution policy')
        name, op, timeout, codes = cells
        if ((name != '*' and name not in methods) or op not in operations
                or not re.fullmatch(r'0|[1-9][0-9]{0,4}', timeout) or int(timeout) > 86400
                or (name, op) in policies):
            raise PolicyError('Invalid installation execution policy')
        accepted = []
        for code in codes.split(','):
            if (not re.fullmatch(r'0|[1-9][0-9]{0,4}', code) or int(code) > 65535
                    or int(code) in (124, 130, 143) or int(code) in accepted):
                raise PolicyError('Invalid installation success code')
            accepted.append(int(code))
        if 0 not in accepted or (op in ('probe', 'download') and codes != '0'):
            raise PolicyError('Invalid success policy for operation')
        policies[name, op] = ExecutionPolicy(int(timeout), accepted)
    for op in operations:
        if ('*', op) not in policies:
            raise PolicyError(f'Missing default execution policy: {op}')
    if (method, operation) in policies:
        return policies[method, operation]
    if ('*', operation) not in policies:
        raise PolicyError(f'Unknown execution operation: {operation}')
    return policies['*', operation]


def probe_result(state: str) -> dict[str, str]:
    if re.search('[|\r\n]', state):
        raise PolicyError('Invalid installation probe delimiters')
    for pattern, action, reason in rows(ROOT / 'install/schema/probes.tsv'):
        if re.search(pattern, state):
            return {'Action': action, 'Reason': reason}
    raise PolicyError(f'Invalid installation probe state: {state}')


@dataclass(frozen=True)
class Decision:
    Action: str
    Reason: str
    State: str
    DecisionReason: str

    def text(self) -> str:
        return '|'.join((self.Action, self.Reason, self.State, self.DecisionReason))


def install_decision(state: str, mode: str, probe_command: str = '', command_present: bool = False,
                     discovery: bool = False) -> Decision:
    if mode not in ('normal', 'resume'):
        raise PolicyError('Invalid installation decision mode')
    if state == 'upgrade':
        state = 'present'
    result = probe_result(state)
    action, reason = result['Action'], result['Reason']
    if action != 'skip' and command_present:
        action, reason = 'skip', 'already-installed'
        if mode == 'resume':
            state = 'present'
    if mode == 'resume':
        if action == 'skip':
            reason = 'resume-already-installed'
        elif not state and not probe_command:
            reason = 'resume-recheck-required'
    return Decision(action, reason, state, 'no-discovery-match' if discovery and not state else reason)


def execution_result(code: int, dry: bool) -> dict[str, str]:
    if code == 0 and dry:
        return {'Status': 'planned', 'Reason': 'dry-run'}
    for value, status, reason in rows(ROOT / 'workflow/schema/outcomes.tsv'):
        if int(value) == code:
            return {'Status': status, 'Reason': reason}
    return {'Status': 'failed', 'Reason': f'exit-{code}'}
