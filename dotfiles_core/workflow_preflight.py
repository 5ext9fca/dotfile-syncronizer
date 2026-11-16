"""Non-mutating workflow preparation over explicit platform observations."""
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Protocol
import re

from dotfiles_core.apply_planning import Entry, Paths, safe
from dotfiles_core.apply_rules import read_items
from dotfiles_core.errors import CoreError
from dotfiles_core.install_planning import components
from dotfiles_core.workflow_review import resume, filter_stages
from dotfiles_core.workflow_rules import read_profile, stage_plan, SelectedStage, will_install


class PreflightError(CoreError):
    pass


class PreflightInputError(PreflightError):
    exit_code = 2


@dataclass(frozen=True)
class Inputs:
    repo: str
    platform: str
    style: str
    profile: str
    session_id: str
    config: str
    backup: str
    dry: bool
    plan_only: bool
    mirrors: bool
    results: str = ''
    only: str = ''
    start: str = ''
    resume_session: str = ''
    mirrors_explicit: bool = False
    # Host adapter inputs (account, executable locations, WSL paths, etc.).
    native: dict = field(default_factory=dict)
    roots: dict[str, str] = field(default_factory=dict)
    profile_explicit: bool = False


@dataclass(frozen=True)
class Prepared:
    inputs: Inputs
    session: str
    profile: dict[str, str]
    stages: tuple[SelectedStage, ...]
    installation: list[dict]
    components: list[str]
    configuration: list[dict]
    mirrors: list[dict]
    wsl: dict | None
    resume_stages: tuple[str, ...]


class Operations(Protocol):
    def resolve_root(self, path: str) -> str: ...
    def entry(self, path: str) -> Entry: ...
    def anchor(self, path: str) -> str: ...
    def command_present(self, name: str) -> bool: ...
    def installation(self, inputs: Inputs, profile: dict, session: str, mode: str) -> list[dict]: ...
    def configuration(self, inputs: Inputs, session: str, selection: list[str]) -> list[dict]: ...
    def mirrors(self, inputs: Inputs, session: str) -> list[dict]: ...
    def mirror_config(self, inputs: Inputs) -> None: ...
    def shell(self, inputs: Inputs, installing_fish: bool) -> None: ...
    def git_path(self, inputs: Inputs) -> str: ...
    def git_probe(self, inputs: Inputs, executable: str, key: str) -> None: ...
    def wsl(self, inputs: Inputs, profile: dict) -> dict: ...


def assert_output(path: str, protected: list[str], operations: Operations, paths: Paths, style: str) -> None:
    safe(path)
    if operations.entry(path).kind != 'absent':
        raise PreflightError(f'Workflow output already exists: {path}')
    if any(paths.overlaps(path, root) for root in protected):
        raise PreflightError(f'Workflow output overlaps repository or configuration: {path}')
    parent = paths.parent(path)
    if style == 'windows':
        # Preserve rejection of reparse/file ancestors, even when the nearest
        # existing descendant itself appears to be a normal directory.
        parent = operations.resolve_root(parent)
    parent = operations.anchor(parent)
    entry = operations.entry(parent)
    if entry.kind != 'directory' or (style == 'unix' and not entry.writable):
        raise PreflightError(f'Workflow output parent is not writable: {parent}')


def validate_plan_outputs(outputs: list[str], rows: list[dict], paths: Paths) -> None:
    for row in rows:
        for output in outputs:
            if output and any(row.get(key) and paths.overlaps(output, row[key]) for key in ('source', 'target')):
                raise PreflightError(f'Workflow output overlaps a planned file: {output}')


def prepare(inputs: Inputs, operations: Operations, paths: Paths) -> Prepared:
    """Finish every selected prerequisite before session creation or execution."""
    if (inputs.style not in ('unix', 'windows')
            or not re.fullmatch('[a-z][a-z0-9-]*', inputs.profile)
            or not re.fullmatch('[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}', inputs.session_id)):
        raise PreflightInputError('Invalid workflow identity')
    if any(type(value) is not bool for value in (inputs.dry, inputs.plan_only, inputs.mirrors, inputs.mirrors_explicit)):
        raise PreflightInputError('Invalid workflow boolean')
    remaining = ()
    if inputs.resume_session:
        saved = resume(Path(inputs.resume_session), inputs.platform, inputs.profile, inputs.style,
                       inputs.only, inputs.start, inputs.mirrors_explicit, inputs.profile_explicit)
        inputs = replace(inputs, profile=saved['profile'], resume_session=saved['session'], mirrors=saved['china_mirrors'] == '1')
        remaining = tuple(saved['resume_stages'])
    profile = read_profile(Path(inputs.repo) / 'workflow/profiles' / (inputs.profile + '.conf'))
    if profile['schema_version'] == '3':
        from dotfiles_core.software import read_catalog, installation_roots
        catalog = read_catalog(Path(inputs.repo) / 'software/items')
        ids = installation_roots(catalog, inputs.platform, 'wsl' if inputs.native.get('inside_wsl') else 'native', profile['install'].split())
        profile['install'] = ' '.join(ids) or 'none'
    if inputs.style == 'unix' and profile['wsl'] != 'none':
        raise PreflightError('Unix profiles require wsl=none')
    if inputs.style == 'windows' and profile['shell'] != 'none':
        raise PreflightError('Windows requires shell=none and mirrors=none; WSL owns Unix initialization.')
    if not inputs.mirrors_explicit and not inputs.resume_session:
        inputs = replace(inputs, mirrors=profile['mirrors'] == 'initialize')
    stages = stage_plan(inputs.style, profile, inputs.only, inputs.start, inputs.mirrors)
    if remaining:
        stages = [SelectedStage(**stage) for stage in filter_stages([stage.document() for stage in stages], list(remaining))]
    inputs = replace(inputs, backup=operations.resolve_root(inputs.backup))
    session = paths.join(inputs.backup, 'workflow-' + inputs.session_id)
    installation = (operations.installation(inputs, profile, session, 'resume' if remaining else 'normal')
                    if profile['install'] != 'none' else [])
    definitions = [] if profile['schema_version'] == '3' else read_items(Path(inputs.repo) / 'apply/items', inputs.style)
    available = [item.id for item in definitions]
    selection = components(profile['components'], installation, available)
    enabled = [stage for stage in stages if stage.Enabled]
    roots = dict(inputs.roots) if inputs.roots else {'config_home': inputs.config, 'local_app_data': inputs.config}
    protected = [inputs.repo]
    for key in {item.target_root for item in definitions if item.id in selection}:
        value = roots.get(key, '')
        if not value or not paths.module.isabs(value):
            raise PreflightError(f'Missing or non-absolute target root: {key}')
        roots[key] = operations.resolve_root(value)
        if key != 'home':
            protected.append(roots[key])
    inputs = replace(inputs, roots=roots, config=roots.get('config_home' if inputs.style == 'unix' else 'local_app_data', inputs.config))
    if inputs.style == 'windows' and any(stage.Preflight == 'git' for stage in enabled):
        protected += inputs.native.get('git_config_paths', [])
    assert_output(session, protected, operations, paths, inputs.style)
    if inputs.results:
        # Keep Windows' lexical full path, while Unix resolves its parent.
        if inputs.style == 'windows':
            results = paths.module.abspath(inputs.results)
            parent = paths.parent(results)
        else:
            parent = operations.resolve_root(paths.module.dirname(inputs.results) or '.')
            results = paths.join(parent, paths.module.basename(inputs.results))
        inputs = replace(inputs, results=results)
        assert_output(results, [*protected, session], operations, paths, inputs.style)
        entry = operations.entry(parent)
        if entry.kind != 'directory' or (inputs.style == 'unix' and not entry.writable):
            raise PreflightError('Results parent must exist and be writable')
    configuration, mirrors, wsl = [], [], None
    mutating = not inputs.dry and not inputs.plan_only
    for stage in enabled:
        match stage.Preflight:
            case 'packages':
                if inputs.style == 'unix':
                    if inputs.mirrors:
                        operations.mirror_config(inputs)
                    if mutating and not operations.command_present('sudo'):
                        raise PreflightError('Packages require sudo')
                elif not operations.command_present('winget.exe'):
                    raise PreflightError('WinGet is required; install Microsoft App Installer first.')
            case 'configuration':
                configuration = operations.configuration(inputs, session, selection) if selection else []
            case 'mirrors':
                mirrors = operations.mirrors(inputs, session)
            case 'shell':
                installing = will_install(stages, installation, 'fish')
                operations.shell(inputs, installing)
            case 'git':
                executable = operations.git_path(inputs)
                if operations.entry(executable).kind == 'absent':
                    if not (any(current.Action == 'packages' for current in enabled) and any(item['id'] == 'git' for item in installation)):
                        raise PreflightError('Git stage requires an installed Git executable or the selected git item.')
                else:
                    for setting in inputs.native.get('git_settings', []):
                        operations.git_probe(inputs, executable, setting['Key'])
            case 'wsl':
                wsl = operations.wsl(inputs, profile)
            case _:
                raise PreflightError(f'Unsupported workflow prerequisite: {stage.Preflight}')
    validate_plan_outputs([session, inputs.results], configuration + mirrors, paths)
    if inputs.style == 'unix':
        combined = [*configuration, *mirrors]
        targets = [row['target'] for row in combined if row.get('source') and row['reason'] != 'excluded']
        if len(targets) != len(set(targets)):
            raise PreflightError('Overlapping configuration and mirror targets')
        validate_plan_outputs([session, inputs.results], combined, paths)
        if inputs.results and any(inputs.results in (row.get('source'), row['target']) for row in combined):
            raise PreflightError('Result file overlaps a deployment source or destination')
        if mutating and any(row['privilege'] == 'sudo' for row in combined) and not operations.command_present('sudo'):
            raise PreflightError('Selected file operations require sudo')
    return Prepared(inputs, session, profile, tuple(stages), installation, selection,
                    configuration, mirrors, wsl, remaining)
