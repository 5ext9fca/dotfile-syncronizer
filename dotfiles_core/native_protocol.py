"""Allowlisted native installation/publication operations and wire projections."""
from pathlib import Path
import json

from dotfiles_core.contracts import Contract
from dotfiles_core.errors import ProtocolError
from dotfiles_core.protocol import Request, Result, write_json

OPERATIONS = frozenset(('install-command', 'publish-report', 'discovery-path',
                        'install-state', 'install-command-probe', 'install-target-check', 'apply-query', 'apply-render', 'workflow-stage', 'workflow-query', 'workflow-prepare-command', 'apply-effect', 'apply-restore', 'workflow-shell-command'))

APPLY_BOOLEAN_QUERIES = frozenset(('equal-copy', 'equal-hardlink', 'desktop-supported', 'file', 'exists', 'directory', 'readonly'))
APPLY_QUERIES = frozenset(('entry', 'state', 'tree', 'anchor', 'identity', 'desktop-families', 'desktop-required',
                          'resolve-root', 'physical-directory', 'permissions', 'go-env', 'manjaro-branch', 'mirror-sources')) | APPLY_BOOLEAN_QUERIES


def validate_item(item: object) -> None:
    if not isinstance(item, dict) or str(item.get('schema_version')) != Contract.load('install-plan').version:
        raise ProtocolError('Invalid native installation item')
    if item.get('action') not in ('install', 'upgrade', 'skip'):
        raise ProtocolError('Invalid native installation action')
    Contract.load('install-plan').row(item)


def validate(request: Request) -> None:
    if request.operation not in OPERATIONS:
        raise ProtocolError('Unsupported native operation')
    context = request.context
    if request.operation == 'workflow-shell-command':
        if (set(context) != {'directory'} or not isinstance(context['directory'], str)
                or '\0' in context['directory']):
            raise ProtocolError('Invalid native shell action')
    elif request.operation == 'apply-restore':
        if (set(context) != {'journal', 'dry'} or not isinstance(context['journal'], str)
                or '\0' in context['journal'] or type(context['dry']) is not bool):
            raise ProtocolError('Invalid native restore request')
    elif request.operation == 'apply-effect':
        if (set(context) != {'action', 'path', 'row', 'sequence'}
                or context['action'] not in ('start', 'transaction', 'preview')
                or not isinstance(context['path'], str) or '\0' in context['path']
                or type(context['sequence']) is not int or context['sequence'] < 0
                or not isinstance(context['row'], dict)):
            raise ProtocolError('Invalid native apply effect')
        if context['action'] in ('transaction', 'preview'):
            Contract.load('apply-plan').row(context['row'])
        elif context['row'] or context['sequence']:
            raise ProtocolError('Invalid apply journal request')
    elif request.operation == 'workflow-prepare-command':
        if (set(context) != {'action', 'dry'} or type(context['dry']) is not bool
                or context['action'] not in ('apt-update', 'pacman-upgrade', 'pacman-remove-rust-analyzer')):
            raise ProtocolError('Invalid native package preparation')
    elif request.operation == 'workflow-query':
        from dotfiles_core.workflow_observation import validate as validate_query
        validate_query(context)
    elif request.operation == 'workflow-stage':
        if set(context) != {'directory', 'action', 'report', 'metadata', 'log', 'style', 'native_context'}:
            raise ProtocolError('Invalid native workflow stage request')
        actions = {'unix': ('packages', 'configuration', 'mirrors', 'shell'),
                   'windows': ('packages', 'git', 'configuration', 'wsl')}
        if context['style'] not in actions or context['action'] not in actions[context['style']]:
            raise ProtocolError('Unknown native workflow action')
        if not isinstance(context['native_context'], dict):
            raise ProtocolError('Invalid native workflow context')
        if not all(isinstance(value, str) and '\0' not in value for key, value in context.items() if key != 'native_context'):
            raise ProtocolError('Invalid native workflow stage field')
    elif request.operation == 'publish-report':
        if set(context) != {'path', 'text', 'mode'} or context['mode'] not in ('replace', 'create'):
            raise ProtocolError('Invalid native publication request')
        if not all(isinstance(context[key], str) for key in context):
            raise ProtocolError('Invalid native publication field')
    elif request.operation == 'apply-render':
        if set(context) != {'kind', 'target', 'candidate', 'fontconfig'} or context['kind'] not in ('kdeglobals', 'gtk-3.0/settings.ini', 'gtk-4.0/settings.ini'):
            raise ProtocolError('Invalid desktop rendering request')
        if not all(isinstance(value, str) and '\0' not in value for value in context.values()):
            raise ProtocolError('Invalid desktop rendering path')
    elif request.operation == 'apply-query':
        if set(context) != {'query', 'path', 'other'} or context['query'] not in APPLY_QUERIES:
            raise ProtocolError('Invalid native apply query')
        if not all(isinstance(value, str) and '\0' not in value for value in context.values()):
            raise ProtocolError('Invalid native apply query argument')
    elif request.operation == 'discovery-path':
        if set(context) != {'kind', 'root', 'relative', 'native_context'}:
            raise ProtocolError('Invalid native discovery request')
        if context['kind'] not in ('file', 'directory') or not all(isinstance(context[key], str) for key in ('root', 'relative')):
            raise ProtocolError('Invalid native discovery path')
    else:
        if set(context) - {'policy_path'} != {'item', 'native_context', 'mode'} or context['mode'] not in ('normal', 'resume'):
            raise ProtocolError('Invalid native installation request')
        if not isinstance(context.get('policy_path', ''), str):
            raise ProtocolError('Invalid native execution policy path')
        item = context['item']
        validate_item(item)


def arguments(request_path: Path, output: Path, platform: str) -> None:
    request = Request.read(request_path)
    validate(request)
    if platform == 'windows':
        if request.operation in ('workflow-prepare-command', 'workflow-shell-command'):
            raise ProtocolError('Unix-only workflow action')
        if request.operation in ('workflow-stage', 'workflow-query') and request.context['style'] != 'windows':
            raise ProtocolError('Workflow adapter style mismatch')
        if request.operation not in ('publish-report', 'apply-query', 'apply-render', 'apply-effect', 'apply-restore') and not isinstance(request.context['native_context'], dict):
            raise ProtocolError('Windows native context must be an object')
        # PowerShell consumes the validated JSON directly.
        return
    if platform != 'unix':
        raise ProtocolError('Unknown native adapter platform')
    context = request.context
    if request.operation == 'workflow-shell-command':
        values = [request.operation, context['directory'], '', '', '']
    elif request.operation == 'apply-restore':
        values = [request.operation, context['journal'], str(int(context['dry'])), '', '']
    elif request.operation == 'apply-effect':
        row = Contract.load('apply-plan').row(context['row']) if context['row'] else ''
        values = [request.operation, context['action'], context['path'], row, str(context['sequence'])]
    elif request.operation == 'workflow-prepare-command':
        values = [request.operation, context['action'], str(int(context['dry'])), '', '']
    elif request.operation == 'workflow-query':
        from dotfiles_core.workflow_observation import arguments as query_arguments
        values = query_arguments(context, platform)
    elif request.operation == 'workflow-stage':
        if context['style'] != 'unix':
            raise ProtocolError('Workflow adapter style mismatch')
        values = [request.operation, context['directory'], context['action'], context['report'], context['metadata'], context['log']]
    elif request.operation == 'publish-report':
        values = [request.operation, context['path'], context['text'], context['mode']]
    elif request.operation == 'apply-render':
        values = [request.operation, context['kind'], context['target'], context['candidate'], context['fontconfig']]
    elif request.operation == 'apply-query':
        values = [request.operation, context['query'], context['path'], context['other'], '']
    elif request.operation == 'discovery-path':
        values = [request.operation, context['kind'], context['root'], context['relative'], context['native_context']]
    else:
        values = [request.operation, Contract.load('install-plan').row(context['item']), context['native_context'], context['mode'], context.get('policy_path', '')]
    if any(not isinstance(value, str) or '\0' in value for value in values):
        raise ProtocolError('Unsupported native argument')
    output.write_bytes(('\0'.join(values) + '\0').encode('utf-8'))


def finish(request_path: Path, result_path: Path, code: int, payload: Path, platform: str) -> None:
    request = Request.read(request_path)
    validate(request)
    data = {}
    if code == 0 and request.operation == 'workflow-query':
        from dotfiles_core.workflow_observation import result as query_result
        data = query_result(request.context, payload)
    elif code == 0 and request.operation == 'workflow-stage':
        if platform == 'windows':
            data = json.loads(payload.read_text(encoding='utf-8-sig'))
            if (not isinstance(data, dict) or set(data) != {'exit_code', 'reason'}
                    or type(data['exit_code']) is not int or not isinstance(data['reason'], str)):
                raise ProtocolError('Invalid native workflow stage result')
        else:
            value = payload.read_text(encoding='utf-8').strip()
            if not value.isascii() or not value.isdecimal() or int(value) > 255:
                raise ProtocolError('Invalid native workflow stage exit code')
            data = {'exit_code': int(value), 'reason': ''}
    elif code == 0 and request.operation == 'apply-query':
        text = payload.read_text(encoding='utf-8-sig').rstrip('\n')
        query = request.context['query']
        if query == 'entry':
            data = json.loads(text)
        elif query in ('tree', 'mirror-sources'):
            data = {'paths': text.splitlines() if text else []}
        elif query in APPLY_BOOLEAN_QUERIES:
            if text not in ('0', '1'):
                raise ProtocolError('Invalid native apply boolean')
            data = {'value': text == '1'}
        else:
            data = {'value': text}
    elif code == 0 and request.operation == 'discovery-path':
        path = json.loads(payload.read_text(encoding='utf-8-sig'))
        if not isinstance(path, str):
            raise ProtocolError('Invalid native path result')
        data = {'path': path}
    elif code == 0 and request.operation == 'install-state':
        data = {'state': payload.read_text(encoding='utf-8-sig').rstrip('\n')}
    elif code == 0 and request.operation == 'install-command-probe':
        present = payload.read_text(encoding='utf-8-sig').strip()
        if present not in ('0', '1'):
            raise ProtocolError('Invalid native command presence result')
        data = {'present': present == '1'}
    write_json(result_path, Result(request.operation, code, data).document())
