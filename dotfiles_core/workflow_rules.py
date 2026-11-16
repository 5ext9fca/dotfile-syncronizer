"""Profile declarations and stage selection; no platform observation or mutation."""
from collections.abc import Sequence
from dataclasses import asdict, dataclass
from pathlib import Path
import re

from dotfiles_core.errors import CoreError
from dotfiles_core.install_config import ROOT, rows


class WorkflowRuleError(CoreError):
    pass


class SelectionError(WorkflowRuleError):
    exit_code = 2


def settings(text: str) -> dict[str, str]:
    return dict(line.split('=', 1) for line in text.splitlines() if '=' in line)


def profile_fields() -> list[tuple[str, str, str]]:
    return [tuple(row) for row in rows(ROOT / 'workflow/schema/profile-context-fields.tsv')]


def read_profile(path: Path) -> dict[str, str]:
    from dotfiles_viewer.api import catalog_root
    if path.parent.resolve() == (ROOT / 'workflow/profiles').resolve():
        path = catalog_root() / 'workflow/profiles' / path.name
    if 'schema_version=3' in path.read_text(encoding='utf-8-sig').splitlines():
        from dotfiles_core.software import profile_selection
        from dotfiles_core.install_config import DeclarationError
        try:
            names = profile_selection(path)
        except DeclarationError as exc:
            raise WorkflowRuleError(str(exc)) from exc
        return dict(schema_version='3', install=' '.join(names), components='none',
                    shell='none', mirrors='none', wsl='none', wsl_profile='none')
    if path.parent.resolve() == (ROOT / 'workflow/profiles').resolve():
        raise WorkflowRuleError('Legacy profiles must migrate to schema_version=3 and software selection')
    schema = {key: (pattern, required) for key, pattern, required in profile_fields()}
    values: dict[str, str] = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        if not line or line.startswith('#'):
            continue
        key, separator, value = line.partition('=')
        if not separator:
            raise WorkflowRuleError('Workflow profile: expected key=value')
        if key not in schema:
            raise WorkflowRuleError(f'Unknown profile field {key}')
        if key in values:
            raise WorkflowRuleError(f'Duplicate profile field {key}')
        if not re.fullmatch(schema[key][0], value):
            raise WorkflowRuleError(f'Invalid profile {key}')
        if key == 'install' and value not in ('none', 'all') and set(value.split()) & {'none', 'all'}:
            raise WorkflowRuleError('Reserved install selector')
        if key == 'components' and value != 'none' and any(pair.split(':')[0] == 'none' for pair in value.split()):
            raise WorkflowRuleError('Reserved component selector')
        if key == 'components':
            components = [pair.split(':')[0] for pair in value.split(' ')]
            if len(components) != len(set(components)):
                raise WorkflowRuleError('Duplicate component')
        values[key] = value
    for key, (_, required) in schema.items():
        if required == 'yes' and key not in values:
            raise WorkflowRuleError(f'Missing profile field {key}')
    if (values['wsl'] == 'none') != (values['wsl_profile'] == 'none'):
        raise WorkflowRuleError('wsl and wsl_profile must both be enabled or none')
    return {key: values[key] for key in schema if key in values}


def profile_text(profile: dict[str, str]) -> list[str]:
    return [f'{key}={profile[key]}' for key, _, _ in profile_fields() if key in profile]


@dataclass(frozen=True)
class Stage:
    Id: str
    Order: int
    Gate: str
    Preflight: str
    Action: str


@dataclass(frozen=True)
class SelectedStage:
    Id: str
    Enabled: bool
    Reason: str
    Preflight: str
    Action: str

    def text(self) -> str:
        return f'{self.Id}|{int(self.Enabled)}|{self.Reason}|{self.Preflight}|{self.Action}'

    def document(self) -> dict:
        return asdict(self)


def read_stages(platform: str, path: Path = ROOT / 'workflow/schema/stages.tsv') -> list[Stage]:
    records = []
    seen = set()
    handlers = {'packages', 'git', 'configuration', 'mirrors', 'shell', 'wsl'}
    for cells in rows(path):
        if len(cells) != 6:
            raise WorkflowRuleError('Invalid stage registry row')
        host, order, name, gate, preflight, action = cells
        if (host not in ('unix', 'windows') or not re.fullmatch('[0-9]{1,6}', order)
                or not re.fullmatch('[a-z][a-z0-9-]*', name) or gate not in ('always', 'install', 'components', 'mirrors', 'shell', 'wsl')
                or preflight not in handlers or action not in handlers):
            raise WorkflowRuleError('Invalid stage registry fields')
        forbidden = {'git', 'wsl'} if host == 'unix' else {'mirrors', 'shell'}
        if preflight in forbidden or action in forbidden:
            raise WorkflowRuleError(f'Unsupported {host} handler')
        if (host, name) in seen:
            raise WorkflowRuleError(f'Duplicate stage {name}')
        seen.add((host, name))
        if host == platform:
            records.append(Stage(name, int(order), gate, preflight, action))
    if not records:
        raise WorkflowRuleError(f'Unknown stage platform {platform}')
    return sorted(records, key=lambda record: (record.Order, record.Id))


def stage_plan(platform: str, profile: dict[str, str], only: str = '', start: str = '', mirrors: bool = True,
               registry: Path = ROOT / 'workflow/schema/stages.tsv') -> list[SelectedStage]:
    if only and start:
        raise SelectionError('OnlyStage and FromStage are mutually exclusive')
    records = read_stages(platform, registry)
    names = {record.Id for record in records}
    for name in (only, start):
        if name and name not in names:
            raise WorkflowRuleError(f'Unknown workflow stage {name}')
    reached = not start
    result = []
    for record in records:
        reached = reached or record.Id == start
        enabled = reached and (not only or record.Id == only)
        reason = '' if enabled else 'selection'
        if enabled and record.Gate not in ('always', 'mirrors') and profile.get(record.Gate) == 'none':
            enabled, reason = False, 'profile'
        if enabled and record.Gate == 'mirrors' and not mirrors:
            enabled, reason = False, 'disabled'
        result.append(SelectedStage(record.Id, enabled, reason, record.Preflight, record.Action))
    return result


def parse_stage_plan(text: str) -> list[SelectedStage]:
    result = []
    for line in text.splitlines():
        fields = line.split('|')
        if len(fields) != 5 or fields[1] not in ('0', '1'):
            raise WorkflowRuleError('Invalid native workflow stage plan')
        identity, enabled, reason, prerequisite, action = fields
        result.append(SelectedStage(identity, enabled == '1', reason, prerequisite, action))
    return result


def will_install(stages: Sequence[SelectedStage], items: Sequence[dict], identity: str) -> bool:
    return (any(stage.Enabled and stage.Action == 'packages' for stage in stages)
            and any(item['id'] == identity for item in items))
