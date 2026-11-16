"""Shared shell prerequisites and stage coordination; login changes stay native."""
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from dotfiles_core.apply_planning import Entry, Paths
from dotfiles_core.contracts import Contract
from dotfiles_core.errors import ProtocolError
from dotfiles_core.workflow_packages import boolean
from dotfiles_core.workflow_preflight import PreflightError
from dotfiles_core.workflow_rules import parse_stage_plan, will_install


@dataclass(frozen=True)
class ShellSettings:
    platform: str
    user: str
    brew_prefix: str
    dry: bool
    plan_only: bool


class Observations(Protocol):
    def entry(self, path: str) -> Entry: ...
    def query(self, name: str, arguments: list[str]): ...
    def command_present(self, name: str) -> bool: ...
    def string(self, name: str, arguments: list[str]) -> str: ...
    def boolean(self, name: str, arguments: list[str]) -> bool: ...


def preflight(settings: ShellSettings, installing_fish: bool, native: Observations) -> None:
    if not native.entry('/etc/shells').readable:
        raise PreflightError('/etc/shells is not readable')
    if native.query('shell-account', [settings.platform, settings.user]) is not None:
        raise ProtocolError('Malformed account observation')
    if not native.command_present('chsh'):
        raise PreflightError('chsh is required for the shell stage')
    if not installing_fish:
        fish = native.string('fish-path', [settings.platform, settings.brew_prefix])
        if not native.boolean('executable', [fish]):
            raise PreflightError('Install Fish before selecting the shell stage')
    if not settings.dry and not settings.plan_only and not native.command_present('sudo'):
        raise PreflightError('The shell stage requires sudo')


OPERATIONS = frozenset(('workflow-shell-native',))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation not in OPERATIONS:
        raise ProtocolError('Unknown workflow shell request')
    from dotfiles_core.native_preflight import NativePreflight
    directory = Path(context['directory'])
    def read(name: str) -> str:
        return (directory / name).read_text(encoding='utf-8').rstrip('\n')
    settings = ShellSettings(read('platform'), read('user'), read('brew_prefix'),
                             boolean(read('dry_run')), boolean(read('plan_only')))
    stages = parse_stage_plan(read('stages.plan'))
    schema = Contract.load('install-plan')
    items = schema.read(schema.from_rows(read('install.plan'), validate_plan=True))
    native = NativePreflight('unix', context['native_shell'], Paths())
    preflight(settings, will_install(stages, items, 'fish'), native)
    native.adapter.operations['workflow-shell-command'] = native.adapter.operations['workflow-query']
    result = native.adapter.invoke('workflow-shell-command', {'directory': str(directory)})
    if result.data:
        raise ProtocolError('Malformed native shell result')
    return None, []
