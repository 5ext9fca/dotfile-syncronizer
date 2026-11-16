"""Standalone apply/mirror/recovery coordination under a native deployment lease."""
from datetime import datetime
from pathlib import Path
import os
import tempfile
import uuid

from dotfiles_core.apply_execution import NativeExecution, execute
from dotfiles_core.apply_rules import validate_plan
from dotfiles_core.contracts import Contract
from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.native_apply import request as plan_request
from dotfiles_core.mirror_planning import request as mirror_request
from dotfiles_core.workflow_packages import boolean


def session_path(backup: str, style: str, owner: str, exists) -> str:
    if style == 'windows':
        return os.path.join(backup, 'apply-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex)
    if not owner.isascii() or not owner.isdecimal():
        raise ProtocolError('Invalid apply owner process ID')
    suffix = 0
    while True:
        name = 'apply-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + owner
        candidate = os.path.join(backup, name + (f'.{suffix}' if suffix else ''))
        if not exists(candidate):
            return candidate
        suffix += 1


def restore(native: NativeExecution, journal: str, dry: bool) -> None:
    command = native.adapter.operations['apply-query']
    native.adapter.operations['apply-restore'] = command
    result = native.adapter.invoke('apply-restore', {'journal': journal, 'dry': dry})
    if result.data:
        raise ProtocolError('Malformed native restore result')


OPERATIONS = frozenset(('apply-entry-native', 'apply-restore-native', 'apply-workflow-native'))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation not in OPERATIONS:
        raise ProtocolError('Unknown standalone apply request')
    style = context['style']
    dry = boolean(context['dry'])
    native = NativeExecution(style, context['native_shell'])
    if operation == 'apply-restore-native':
        restore(native, context['journal'], dry)
        return None, []
    preview = boolean(context.get('plan_only', False))
    selection = context.get('selection', [])
    if isinstance(selection, str):
        selection = selection.splitlines()
    journal = context.get('restore', '')
    if journal:
        if selection:
            raise AdapterError('Restore cannot select components', 2 if style == 'unix' else 1)
        restore(native, journal, dry or preview)
        return None, []
    config = context['config']
    if context.get('kind') == 'mirrors' or boolean(context.get('mirrors', False)):
        if not config or not os.path.isabs(config):
            raise ProtocolError('Missing config_home for mirrors')
        config = native.fs.value('resolve-root', config)
    if operation == 'apply-workflow-native':
        session = context['session']
    else:
        backup = native.fs.value('resolve-root', context['backup'])
        session = session_path(backup, style, str(context.get('owner_pid', '')),
                               lambda path: native.fs.entry(path).kind != 'absent')
    kind = context.get('kind', 'configuration')
    if kind not in ('configuration', 'mirrors') or (kind == 'mirrors' and style != 'unix'):
        raise ProtocolError('Invalid standalone apply kind')
    schema = Contract.load('apply-plan')
    # Candidates and private plans live until execution finishes, including
    # failures. Printed plans retain the existing non-replayable scratch paths.
    with tempfile.TemporaryDirectory(prefix='dotfiles-apply-') as scratch:
        rows = []
        if kind == 'configuration':
            rows, _ = plan_request('apply-plan-native', {
                'style': style, 'native_shell': context['native_shell'],
                'repo': context['repo'], 'items': os.path.join(context['repo'], 'apply/items'),
                'config': config, 'roots': context.get('roots'), 'session': session, 'selection': selection,
                'render_scratch': scratch, 'preview': str(int(dry or preview))})
        if kind == 'mirrors' or boolean(context.get('mirrors', False)):
            if style != 'unix':
                raise ProtocolError('Standalone mirrors are Unix-only')
            rows, _ = mirror_request('mirror-plan-native', {
                'native_shell': context['native_shell'], 'file': context['mirror_config'],
                'mode': context.get('mode', 'apply'), 'config': config, 'session': session,
                'scratch': scratch, 'base_plan': '\n'.join(schema.row(row) for row in rows),
                'system_root': '/', 'manager': context['manager'],
                'cargo_home': context['cargo_home'], 'npm_config': context['npm_config']})
        validate_plan(rows, style)
        if preview:
            document = schema.write(rows)
            return document, document.split('\n')
        code = execute(rows, session, dry, context.get('results', ''), context.get('metadata', ''), style, native)
        if code:
            raise AdapterError('Apply execution failed', code)
    if kind == 'configuration' and operation != 'apply-workflow-native':
        print('Windows configuration applied successfully.' if style == 'windows'
              else 'Configuration applied successfully.', flush=True)
    return None, []
