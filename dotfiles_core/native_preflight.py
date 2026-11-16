"""Platform observations and existing core planners for workflow preflight.

This binding does not execute a workflow stage or create persistent sessions.
Rendered candidates live only for the duration of the planning request.
"""
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
import os
import tempfile

from dotfiles_core.apply_planning import Paths
from dotfiles_core.apply_rules import validate_plan
from dotfiles_core.errors import ProtocolError
from dotfiles_core.install_config import ROOT
from dotfiles_core.native_apply import native_filesystem, request as apply_request
from dotfiles_core.native_installation import native_installation
from dotfiles_core.mirror_planning import config_file, request as mirror_request
from dotfiles_core.protocol import Adapter
from dotfiles_core.workflow_preflight import Inputs, PreflightError

OPERATIONS = frozenset(('workflow-preflight-native',))


@dataclass
class NativePreflight:
    style: str
    shell_path: str
    paths: Paths
    install_context: str | dict = field(default_factory=dict)

    def __post_init__(self):
        self.filesystem = native_filesystem(self.style, self.shell_path)
        command = ([self.shell_path, str(ROOT / 'lib/core-adapter.sh')] if self.style == 'unix' else
                   [self.shell_path, '-NoProfile', '-File', str(ROOT / 'lib/core-adapter.ps1')])
        self.adapter = Adapter({'workflow-query': command})

    def query(self, name: str, arguments: list[str] | None = None, context: dict | None = None):
        data = self.adapter.invoke('workflow-query', dict(query=name, arguments=arguments or [],
                                   native_context=context or {}, style=self.style)).data
        if set(data) != {'value'}:
            raise ProtocolError('Malformed native workflow observation')
        return data['value']

    def string(self, name: str, arguments: list[str] | None = None) -> str:
        value = self.query(name, arguments)
        if not isinstance(value, str):
            raise ProtocolError('Malformed native workflow path')
        return value

    def boolean(self, name: str, arguments: list[str]) -> bool:
        value = self.query(name, arguments)
        if type(value) is not bool:
            raise ProtocolError('Malformed native workflow boolean')
        return value

    def resolve_root(self, path: str) -> str:
        return self.filesystem.value('resolve-root', path)

    def entry(self, path: str):
        return self.filesystem.entry(path)

    def anchor(self, path: str) -> str:
        return self.filesystem.anchor(path)

    def command_present(self, name: str) -> bool:
        return self.boolean('command-present', [name])

    def installation(self, inputs: Inputs, profile: dict, session: str, mode: str) -> list[dict]:
        if self.style == 'unix':
            values = [inputs.platform, str(int(inputs.dry)), inputs.native.get('brew_cmd', ''),
                      inputs.native.get('brew_prefix', ''), self.paths.join(session, 'packages-backups'), '',
                      inputs.native.get('distro_id', ''), inputs.native.get('distro_codename', '')]
            if any(any(character in value for character in '|\r\n') for value in values):
                raise PreflightError('Execution context values cannot contain pipes or newlines')
            self.install_context = '|'.join(values)
        else:
            self.install_context = dict(DryRun=inputs.dry, ProgramFiles=inputs.native['ProgramFiles'],
                                        VsInstallerRoot=inputs.native['VsInstallerRoot'])
        runner = native_installation(self.style, self.shell_path, self.install_context)
        return runner.plan(self.paths.join(inputs.repo, 'install/items'), inputs.platform, inputs.mirrors,
                           bool(inputs.native.get('inside_wsl', False)), profile['install'], mode)

    def apply_session(self, base: str) -> str:
        # Preserve the Unix naming convention without reserving a directory.
        suffix = 0
        while True:
            name = f'apply-{datetime.now():%Y%m%d-%H%M%S}-{os.getpid()}' + (f'.{suffix}' if suffix else '')
            path = self.paths.join(base, name)
            if self.entry(path).kind == 'absent':
                return path
            suffix += 1

    def configuration(self, inputs: Inputs, session: str, selection: list[str]) -> list[dict]:
        destination = self.paths.join(session, 'configuration')
        if self.style == 'unix':
            destination = self.apply_session(destination)
        with tempfile.TemporaryDirectory(prefix='dotfiles-preflight-') as scratch:
            rows, _ = apply_request('apply-plan-native', dict(style=self.style, native_shell=self.shell_path,
                                    repo=inputs.repo, items=self.paths.join(inputs.repo, 'apply/items'),
                                    config=inputs.config, roots=inputs.roots, session=destination, selection=selection,
                                    render_scratch=scratch, preview='1'))
            validate_plan(rows, self.style)
            return rows

    def mirror_config(self, inputs: Inputs) -> None:
        config_file(inputs.native['mirror_config'])

    def mirrors(self, inputs: Inputs, session: str) -> list[dict]:
        with tempfile.TemporaryDirectory(prefix='dotfiles-preflight-') as scratch:
            rows, _ = mirror_request('mirror-plan-native', dict(native_shell=self.shell_path,
                                     file=inputs.native['mirror_config'], mode='initialize', config=inputs.config,
                                     session=self.apply_session(self.paths.join(session, 'mirrors')), scratch=scratch,
                                     base_plan='', system_root='/', manager=self.string('package-manager'),
                                     cargo_home=os.environ.get('CARGO_HOME') or str(Path.home() / '.cargo'),
                                     npm_config=os.environ.get('NPM_CONFIG_USERCONFIG') or str(Path.home() / '.npmrc')))
            validate_plan(rows, 'unix')
            return rows

    def shell(self, inputs: Inputs, installing_fish: bool) -> None:
        from dotfiles_core.workflow_shell import ShellSettings, preflight
        preflight(ShellSettings(inputs.platform, inputs.native['user'], inputs.native.get('brew_prefix', ''),
                                inputs.dry, inputs.plan_only), installing_fish, self)

    def git_path(self, inputs: Inputs) -> str:
        return self.string('git-path', [inputs.native['ProgramFiles']])

    def git_probe(self, inputs: Inputs, executable: str, key: str) -> None:
        if self.query('git-probe', [executable, key]) is not None:
            raise ProtocolError('Malformed Git configuration observation')

    def wsl(self, inputs: Inputs, profile: dict) -> dict:
        value = self.query('wsl-plan', context=dict(RepoRoot=inputs.repo, Profile=profile,
                           NoChinaMirrors=not inputs.mirrors, SessionId=inputs.session_id,
                           DryRun=inputs.dry, ResultsPath=inputs.results))
        if not isinstance(value, dict) or set(value) != {'Arguments', 'Text', 'HostReport'}:
            raise ProtocolError('Malformed WSL preflight result')
        return value


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    from dotfiles_core.contracts import Contract
    from dotfiles_core.workflow_preflight import prepare, PreflightInputError
    from dotfiles_core.workflow_rules import profile_text

    if operation not in OPERATIONS or context['style'] not in ('unix', 'windows'):
        raise ProtocolError('Unsupported native workflow preflight')
    style = context['style']
    paths = Paths(windows=os.name == 'nt', case_insensitive=style == 'windows')
    native = NativePreflight(style, context['native_shell'], paths)
    if style == 'unix':
        directory = Path(context['directory'])

        def value(name: str, default: str | None = None) -> str:
            path = directory / name
            if default is not None and not path.exists():
                return default
            return path.read_text(encoding='utf-8').removesuffix('\n')

        def boolean(name: str, default: str | None = None) -> bool:
            text = value(name, default)
            if text not in ('0', '1'):
                raise PreflightInputError(f'Invalid boolean context: {name}')
            return text == '1'

        # Confirmation remains an entry/native terminal action, but its input
        # must be rejected before any planning observations, as before.
        boolean('assume_yes')
        native_values = {name: value(name, '') for name in ('brew_cmd', 'brew_prefix', 'distro_id',
                         'distro_codename', 'user', 'mirror_config')}
        native_values['inside_wsl'] = boolean('inside_wsl')
        inputs = Inputs(value('repo_root'), value('platform'), style, value('profile_name'), value('session_id'),
                        value('config_home'), value('backup_root'), boolean('dry_run'), boolean('plan_only'),
                        boolean('china_mirrors'), value('results_path'), value('only_stage'), value('from_stage'),
                        value('resume_session', ''), boolean('mirrors_explicit', '0'), native_values,
                        {'home': os.environ.get('HOME', ''), 'config_home': value('config_home')},
                        value('profile_explicit', '') == '1')
    else:
        values = context['native_context']
        inputs = Inputs(values['RepoRoot'], 'windows', style, values['ProfileName'], values['SessionId'],
                        values['ConfigRoot'], paths.parent(values['SessionPath']), values['DryRun'], values['PlanOnly'],
                        not values['NoChinaMirrors'], values.get('ResultsPath') or '', values.get('OnlyStage') or '',
                        values.get('FromStage') or '', values.get('Resume') or '', bool(values.get('MirrorsExplicit')),
                        {'ProgramFiles': values['ProgramFiles'], 'VsInstallerRoot': values['VsInstallerRoot'],
                         'git_config_paths': values['GitConfigPaths'], 'git_settings': values['GitSettings']},
                        values.get('Roots', {}), bool(values.get('ProfileExplicit')))
    prepared = prepare(inputs, native, paths)
    if style == 'windows':
        updates = dict(ProfileName=prepared.inputs.profile, Roots=prepared.inputs.roots, ConfigRoot=prepared.inputs.config, SessionPath=prepared.session,
                       ResultsPath=prepared.inputs.results, Resume=prepared.inputs.resume_session,
                       NoChinaMirrors=not prepared.inputs.mirrors, Profile=prepared.profile,
                       StagePlan=[stage.document() for stage in prepared.stages],
                       InstallContext=native.install_context, InstallPlan=prepared.installation,
                       Components=prepared.components, ApplyPlan=prepared.configuration, WslPlan=prepared.wsl)
        if prepared.inputs.resume_session:
            updates['ResumeStages'] = list(prepared.resume_stages)
        return updates, []
    # These files belong to the caller's private context and remain temporary.
    # No persistent session/report is created during preflight.
    documents = dict(profile_name=prepared.inputs.profile, config_home=prepared.inputs.config, session_path=prepared.session,
                     results_path=prepared.inputs.results, china_mirrors=str(int(prepared.inputs.mirrors)),
                     profile='\n'.join(profile_text(prepared.profile)), components='\n'.join(prepared.components))
    documents['stages.plan'] = '\n'.join(stage.text() for stage in prepared.stages)
    documents['install.context'] = native.install_context if isinstance(native.install_context, str) else ''
    for name, kind, rows in (('install.plan', 'install-plan', prepared.installation),
                             ('configuration.plan', 'apply-plan', prepared.configuration),
                             ('mirrors.plan', 'apply-plan', prepared.mirrors)):
        documents[name] = '\n'.join(Contract.load(kind).row(row) for row in rows)
    if prepared.inputs.resume_session:
        documents['resume_session'] = prepared.inputs.resume_session
        documents['resume_stages'] = ','.join(prepared.resume_stages)
    for name, text in documents.items():
        (directory / name).write_text(text + '\n' if text else '', encoding='utf-8')
    return None, []
