"""Installation-stage coordination; platform adapters execute fixed commands."""
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Protocol
import os

from dotfiles_core.contracts import Contract
from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.install_config import ROOT
from dotfiles_core.install_planning import preparation
from dotfiles_core.mirror_planning import config_file
from dotfiles_core.mirror_rules import environment
from dotfiles_core.native_installation import native_installation
from dotfiles_core.protocol import Adapter
from dotfiles_core.workflow_rules import settings


class Preparation(Protocol):
    def packages(self) -> list[str]: ...
    def command(self, action: str, dry: bool) -> None: ...


def boolean(value: object) -> bool:
    if type(value) is bool:
        return value
    if isinstance(value, str) and value in ('0', '1'):
        return value == '1'
    raise ProtocolError('Invalid workflow package boolean')


def prepare(items: list[dict], platform: str, dry: bool, native: Preparation) -> None:
    actions, _ = preparation(platform, items)
    for action in actions:
        if action == 'pacman-rust-conflict':
            if 'rust-analyzer' in native.packages():
                native.command('pacman-remove-rust-analyzer', dry)
        else:
            native.command(action, dry)


@contextmanager
def stage_environment(values: dict[str, str]) -> Iterator[None]:
    previous = {key: os.environ.get(key) for key in values}
    os.environ.update(values)
    try:
        yield
    finally:
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def run(style: str, platform: str, dry: bool, refresh: Callable[[], list[dict]],
        install: Callable[[list[dict]], None], native: Preparation) -> None:
    if style not in ('unix', 'windows'):
        raise ProtocolError('Unknown workflow package style')
    items = refresh()
    if style == 'unix':
        prepare(items, platform, dry, native)
        # Preparation may change current package state; always re-plan before
        # installation. This is not a post-install verification.
        items = refresh()
    install(items)


class NativePreparation:
    def __init__(self, shell: str):
        command = [shell, str(ROOT / 'lib/core-adapter.sh')]
        self.adapter = Adapter({name: command for name in ('workflow-query', 'workflow-prepare-command')})

    def packages(self) -> list[str]:
        data = self.adapter.invoke('workflow-query', dict(style='unix', query='pacman-packages',
                                   arguments=[], native_context={})).data
        if (set(data) != {'value'} or not isinstance(data['value'], list)
                or any(not isinstance(value, str) for value in data['value'])):
            raise ProtocolError('Malformed native package inventory')
        return data['value']

    def command(self, action: str, dry: bool) -> None:
        data = self.adapter.invoke('workflow-prepare-command', {'action': action, 'dry': dry}).data
        if data:
            raise ProtocolError('Malformed native preparation result')


OPERATIONS = frozenset(('workflow-packages-native',))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation not in OPERATIONS:
        raise ProtocolError('Unknown workflow package request')
    shell = context['native_shell']
    if not isinstance(shell, str) or not Path(shell).is_absolute() or not Path(shell).is_file():
        raise ProtocolError('Native shell must be an existing absolute executable path')
    native = NativePreparation(shell)
    style = context['style']
    values = {}
    directory = None
    if style == 'unix':
        directory = Path(context['directory'])

        def read(name: str) -> str:
            return (directory / name).read_text(encoding='utf-8').rstrip('\n')

        repo, platform, dry = read('repo_root'), read('platform'), boolean(read('dry_run'))
        mirrors, wsl = boolean(read('china_mirrors')), boolean(read('inside_wsl'))
        profile = settings(read('profile'))
        install_context = read('install.context')
        resume_path = directory / 'resume_stages'
        resumed = resume_path.is_file() and resume_path.stat().st_size > 0
        if mirrors:
            values = dict(environment(config_file(read('mirror_config')), ROOT / 'mirrors/schema/environment.tsv'))
            values['HOMEBREW_INSTALL_FROM_API'] = '1'
    elif style == 'windows':
        current = context['native_context']
        repo, platform, dry = current['RepoRoot'], 'windows', boolean(current['DryRun'])
        mirrors, wsl, profile = not boolean(current.get('NoChinaMirrors', False)), False, current['Profile']
        resumed = bool(current.get('Resume'))
        install_context = {**current['InstallContext'], 'ResumeItems': resumed}
    else:
        raise ProtocolError('Unknown workflow package style')
    runner = native_installation(style, shell, install_context)

    def refresh() -> list[dict]:
        items = runner.plan(str(Path(repo) / 'software/items'), platform, mirrors, wsl,
                            profile['install'], 'resume' if resumed else 'normal')
        if directory is not None:
            schema = Contract.load('install-plan')
            (directory / 'install.plan').write_text(''.join(schema.row(item) + '\n' for item in items), encoding='utf-8')
        return items

    def install(items: list[dict]) -> None:
        result = runner.execute(items, dry=dry, resume=resumed, results=context['report'], style=style)
        if result.exit_code:
            raise AdapterError('Installation execution failed', result.exit_code)

    with stage_environment(values):
        run(style, platform, dry, refresh, install, native)
    return None, []
