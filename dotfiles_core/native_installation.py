"""Bind the shared installation scheduler to native allowlisted operations."""
from dataclasses import dataclass
from typing import Any

from dotfiles_core.errors import ProtocolError
from dotfiles_core.install_execution import execute, InstallationResult
from dotfiles_core.install_planning import Item, select
from dotfiles_core.protocol import Adapter
from dotfiles_core.native_protocol import validate_item, OPERATIONS as NATIVE_OPERATIONS
from dotfiles_core.native_observation import NativeObservation


@dataclass
class NativeInstallation:
    adapter: Adapter
    context: str | dict[str, Any]
    policy_path: str = ''
    style: str = ''

    def item_context(self, item: Item, mode: str) -> dict:
        return {'item': item, 'native_context': self.context, 'mode': mode, 'policy_path': self.policy_path}

    def observe(self, item: Item, mode: str = 'normal') -> Item:
        style = self.style or ('windows' if isinstance(self.context, dict) else 'unix')
        observed = NativeObservation(self.adapter, self.context, style, self.policy_path).observe(item, mode)
        validate_item(observed)
        return observed

    def install(self, item: Item) -> None:
        result = self.adapter.invoke('install-command', self.item_context(item, 'normal'))
        if result.data:
            raise ProtocolError('Malformed native command result')

    def publish(self, path: str, text: str) -> None:
        result = self.adapter.invoke('publish-report', {'path': path, 'text': text, 'mode': 'replace'})
        if result.data:
            raise ProtocolError('Malformed native publication result')

    def select(self, items: list[Item], roots: str, mode: str) -> list[Item]:
        return select(items, roots, mode, self.observe)

    def plan(self, directory: str, platform: str, mirrors: bool, wsl: bool, roots: str, mode: str) -> list[Item]:
        from dotfiles_core.install_planning import request as planning_request
        items, _ = planning_request('install-prepare', dict(directory=directory, platform=platform,
                                                          mirrors=str(int(mirrors)), wsl=str(int(wsl))))
        return self.select(items, roots, mode)

    def execute(self, items: list[Item], *, dry: bool, resume: bool, results: str = '', style: str = 'unix') -> InstallationResult:
        return execute(items, dry=dry, resume=resume, install=self.install,
                       observe=lambda item: self.observe(item, 'resume'),
                       publish=(lambda text: self.publish(results, text)) if results else None, style=style,
                       policy_path=self.policy_path)


OPERATIONS = frozenset(('install-plan-native', 'install-select-native', 'install-execute-native', 'install-observe-native', 'install-discover-native'))


def native_installation(style: str, shell: str, context: str | dict, policy_path: str = '') -> NativeInstallation:
    from pathlib import Path
    from dotfiles_core.install_config import ROOT
    if not isinstance(shell, str) or not Path(shell).is_absolute() or not Path(shell).is_file():
        raise ProtocolError('Native shell must be an existing absolute executable path')
    if style == 'unix':
        command = [shell, str(ROOT / 'lib/core-adapter.sh')]
    elif style == 'windows':
        command = [shell, '-NoProfile', '-File', str(ROOT / 'lib/core-adapter.ps1')]
    else:
        raise ProtocolError('Unknown native adapter style')
    adapter = Adapter({name: command for name in NATIVE_OPERATIONS})
    return NativeInstallation(adapter, context, policy_path, style)


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    from dotfiles_core.contracts import Contract
    from dotfiles_core.errors import AdapterError
    style = context['style']
    runner = native_installation(style, context['native_shell'], context['native_context'], context.get('policy_path', ''))
    schema = Contract.load('install-plan')
    if operation == 'install-plan-native':
        from dotfiles_core.install_planning import request as planning_request
        items, _ = planning_request('install-prepare', context)
        if str(context['inspect']) == '1':
            if (style == 'windows' and context['platform'] != 'windows'
                    and any(item['action'] != 'skip' for item in items)):
                raise ProtocolError('PowerShell can inspect only the Windows host; use offline planning for other platforms')
            items = runner.select(items, 'all', 'normal')
        return items, [schema.row(item) for item in items]
    if operation == 'install-discover-native':
        observation = NativeObservation(runner.adapter, runner.context, style, runner.policy_path).discover(context['specification'])
        return {'State': observation.state, 'Method': observation.method, 'Paths': observation.evidence()}, [observation.method + '|' + observation.evidence()]
    if operation == 'install-observe-native':
        item = context['item']
        if isinstance(item, str):
            records = schema.read(schema.from_rows(item, validate_plan=True))
            if len(records) != 1:
                raise ProtocolError('Expected one installation observation item')
            item = records[0]
        else:
            item = dict(item)
            item.setdefault('schema_version', schema.version)
            item.setdefault('action', 'install')
            item.setdefault('reason', 'requested')
            item = schema.read(schema.write([item]))[0]
        observed = runner.observe(item, context['mode'])
        return observed, [schema.row(observed)]
    items = context['items']
    if isinstance(items, str):
        items = schema.read(items if items.startswith('# dotfiles|') else schema.from_rows(items, validate_plan=True))
    if operation == 'install-select-native':
        selected = runner.select(items, context['roots'], context['mode'])
        return selected, [schema.row(item) for item in selected]
    if operation == 'install-execute-native':
        result = runner.execute(items, dry=str(context['dry']) == '1', resume=str(context['resume']) == '1',
                                results=context.get('results', ''), style=style)
        if result.exit_code:
            raise AdapterError('Installation execution failed', result.exit_code)
        return {'exit_code': 0, 'rows': list(result.rows)}, []
    raise ProtocolError('Unknown native installation operation')
