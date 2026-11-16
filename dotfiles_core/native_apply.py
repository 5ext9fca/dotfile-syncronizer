"""Read-only native observations for the shared application planner."""
from pathlib import Path
import os
import sys

from dotfiles_core.apply_planning import Entry, Paths, Planner
from dotfiles_core.apply_rules import read_items
from dotfiles_core.contracts import Contract
from dotfiles_core.errors import ProtocolError
from dotfiles_core.install_config import ROOT
from dotfiles_core.protocol import Adapter


class NativeFilesystem:
    def __init__(self, adapter: Adapter):
        self.adapter = adapter

    def query(self, query: str, path: str = '', other: str = '') -> dict:
        return self.adapter.invoke('apply-query', {'query': query, 'path': path, 'other': other}).data

    def value(self, query: str, path: str = '', other: str = '', *, boolean: bool = False):
        result = self.query(query, path, other)
        expected = bool if boolean else str
        if set(result) != {'value'} or type(result['value']) is not expected:
            raise ProtocolError('Malformed native filesystem result')
        return result['value']

    def entry(self, path: str) -> Entry:
        result = self.query('entry', path)
        if (set(result) != {'kind', 'readable', 'writable', 'searchable'}
                or result['kind'] not in ('absent', 'file', 'directory', 'link', 'other')
                or any(type(result[key]) is not bool for key in ('readable', 'writable', 'searchable'))):
            raise ProtocolError('Malformed native filesystem entry')
        return Entry(**result)

    def state(self, path: str) -> str:
        return self.value('state', path)

    def tree(self, path: str) -> list[str]:
        result = self.query('tree', path)
        if set(result) != {'paths'} or not isinstance(result['paths'], list) or any(not isinstance(value, str) for value in result['paths']):
            raise ProtocolError('Malformed native filesystem tree')
        return result['paths']

    def anchor(self, path: str) -> str:
        return self.value('anchor', path)

    def identity(self, path: str) -> str:
        return self.value('identity', path)

    def equal(self, source: str, target: str, method: str) -> bool:
        return self.value('equal-' + method, source, target, boolean=True)


def native_filesystem(style: str, shell: str) -> NativeFilesystem:
    if not isinstance(shell, str) or not Path(shell).is_absolute() or not Path(shell).is_file():
        raise ProtocolError('Native shell must be an existing absolute executable path')
    if style == 'unix':
        command = [shell, str(ROOT / 'lib/core-adapter.sh')]
    elif style == 'windows':
        command = [shell, '-NoProfile', '-File', str(ROOT / 'lib/core-adapter.ps1')]
    else:
        raise ProtocolError('Unknown apply platform')
    return NativeFilesystem(Adapter({name: command for name in ('apply-query',)}))


OPERATIONS = frozenset(('apply-plan-native',))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation not in OPERATIONS:
        raise ProtocolError('Unknown apply planning request')
    style = context['style']
    filesystem = native_filesystem(style, context['native_shell'])
    planner = Planner(filesystem, context['session'], style,
                      Paths(windows=os.name == 'nt', case_insensitive=style == 'windows'))
    schema = Contract.load('apply-plan')
    selection = context.get('selection')
    if isinstance(selection, str):
        selection = [name for name in selection.splitlines() if name] if selection else None
    if selection == ['none']:
        selection = []
    roots = context.get('roots')
    if isinstance(roots, str):
        roots = dict(line.split('|', 1) for line in roots.splitlines() if line) if roots else None
    items = read_items(Path(context['items']), style)
    if roots is None:
        roots = {'config_home': context['config'], 'local_app_data': context['config']}
    selected = [item for item in items if selection is None or item.id in selection]
    for key in {item.target_root for item in selected}:
        value = roots.get(key, '')
        if not value or not planner.paths.module.isabs(value):
            raise ProtocolError(f'Missing or non-absolute target root: {key}')
        roots[key] = filesystem.value('resolve-root', value)
    context = {**context, 'config': roots.get('config_home', context['config'])}
    rows = planner.components(read_items(Path(context['items']), style), context['repo'], context['config'],
                              selection, roots=roots)
    return rows, [schema.row(row) for row in rows]
