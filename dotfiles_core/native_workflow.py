"""Bind session scheduling to fixed native stage and publication operations."""
from dataclasses import dataclass
from pathlib import Path
import shlex
import sys

from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.install_config import ROOT
from dotfiles_core.protocol import Adapter
from dotfiles_core.workflow_rules import parse_stage_plan
from dotfiles_core.workflow_session import Session, Stage, StageExecution, run


@dataclass
class NativeSession:
    adapter: Adapter
    directory: str
    style: str = 'unix'
    context: dict | None = None

    def publish(self, path: Path, text: str, mode: str = 'replace') -> None:
        result = self.adapter.invoke('publish-report', {'path': str(path), 'text': text, 'mode': mode})
        if result.data:
            raise ProtocolError('Malformed native workflow publication result')

    def execute(self, action: str, report: Path, metadata: Path, log: Path) -> StageExecution:
        result = self.adapter.invoke('workflow-stage', dict(directory=self.directory, action=action,
                                     report=str(report), metadata=str(metadata), log=str(log),
                                     style=self.style, native_context=self.context or {}))
        data = result.data
        if (set(data) != {'exit_code', 'reason'} or type(data['exit_code']) is not int
                or not (0 if self.style == 'unix' else -0x80000000) <= data['exit_code'] <= (255 if self.style == 'unix' else 0xffffffff)
                or not isinstance(data['reason'], str)):
            raise ProtocolError('Malformed native workflow stage result')
        return StageExecution(data['exit_code'], data['reason'])


OPERATIONS = frozenset(('workflow-session-native',))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation not in OPERATIONS or context['style'] not in ('unix', 'windows'):
        raise ProtocolError('Unsupported native workflow session')
    shell = Path(context['native_shell'])
    if not shell.is_absolute() or not shell.is_file():
        raise ProtocolError('Native shell must be an existing absolute executable path')
    if context['style'] == 'windows':
        values = context['native_context']
        stages = tuple(Stage(stage['Id'], stage['Enabled'], stage.get('Reason', ''), stage['Action']) for stage in values['StagePlan'])
        session = Session(values['SessionId'], Path(values['SessionPath']), values['ProfileName'], 'windows',
                          'windows', values['DryRun'], not values.get('NoChinaMirrors', False), stages,
                          values.get('ResultsPath', ''), values.get('Resume') or '')
        command = [str(shell), '-NoProfile', '-File', str(ROOT / 'lib/core-adapter.ps1')]
        native = NativeSession(Adapter({name: command for name in ('publish-report', 'workflow-stage')}), '', 'windows', values)
        return execute(session, native)
    directory = Path(context['directory'])

    def value(name: str, default: str | None = None) -> str:
        path = directory / name
        if default is not None and not path.exists():
            return default
        return path.read_text(encoding='utf-8').removesuffix('\n')

    stages = [Stage(stage.Id, stage.Enabled, stage.Reason, stage.Action)
              for stage in parse_stage_plan(value('stages.plan'))]
    session = Session(value('session_id'), Path(value('session_path')), value('profile_name'),
                      value('platform'), 'unix', value('dry_run') == '1', value('china_mirrors') == '1',
                      tuple(stages), value('results_path'), value('resume_session', ''), directory)
    command = [str(shell), str(ROOT / 'lib/core-adapter.sh')]
    native = NativeSession(Adapter({name: command for name in ('publish-report', 'workflow-stage')}), str(directory))
    return execute(session, native)


def execute(session: Session, native: NativeSession) -> tuple[object, list[str]]:
    result = run(session, native, emit=lambda line: print(line, flush=True))
    if result.exit_code:
        windows = session.style == 'windows'
        quoted = "'" + str(session.path).replace("'", "''") + "'" if windows else shlex.quote(str(session.path))
        if session.persistent:
            command = './workflow/status.ps1 -Session' if windows else 'bash workflow/status.sh'
            print(f'Inspect failure: {command} {quoted}', file=sys.stderr)
        if session.persistent and not session.dry:
            option = '-Resume' if windows else '--resume'
            print(f'After resolving the cause, continue with {option} {quoted}; current state is checked again.', file=sys.stderr)
        else:
            options = '-FromStage STAGE or -OnlyStage STAGE' if windows else '--from-stage STAGE or --only-stage STAGE'
            print(f'Retry with {options}; current state is checked again.', file=sys.stderr)
        raise AdapterError('Workflow execution failed', result.exit_code)
    return {'exit_code': 0, 'rows': list(result.rows)}, []
