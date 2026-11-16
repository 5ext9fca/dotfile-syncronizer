"""Allowlist and decoding for read-only native workflow observations."""
import json
from pathlib import Path

from dotfiles_core.errors import ProtocolError

QUERIES = {
    'unix': {'command-present': 1, 'executable': 1, 'package-manager': 0,
             'shell-account': 2, 'fish-path': 2, 'pacman-packages': 0},
    'windows': {'command-present': 1, 'git-path': 1, 'git-probe': 2, 'wsl-plan': 0},
}


def validate(context: dict) -> None:
    if set(context) != {'query', 'arguments', 'native_context', 'style'}:
        raise ProtocolError('Invalid native workflow query fields')
    style, query, arguments = context['style'], context['query'], context['arguments']
    if not isinstance(style, str) or not isinstance(query, str) or query not in QUERIES.get(style, {}):
        raise ProtocolError('Unsupported native workflow query')
    if (not isinstance(arguments, list) or len(arguments) != QUERIES[style][query]
            or any(not isinstance(value, str) or '\0' in value for value in arguments)
            or not isinstance(context['native_context'], dict)):
        raise ProtocolError('Invalid native workflow query arguments')
    if style == 'unix' and context['native_context']:
        raise ProtocolError('Unix workflow observations require explicit arguments')


def arguments(context: dict, platform: str) -> list[str]:
    validate(context)
    if context['style'] != platform:
        raise ProtocolError('Workflow query adapter style mismatch')
    return ['workflow-query', context['query'], *context['arguments'],
            *([''] * (3 - len(context['arguments'])))]


def result(context: dict, payload: Path) -> dict:
    validate(context)
    text = payload.read_text(encoding='utf-8-sig').rstrip('\r\n')
    query = context['query']
    if query in ('command-present', 'executable'):
        if text not in ('0', '1'):
            raise ProtocolError('Invalid workflow observation boolean')
        value = text == '1'
    elif query == 'pacman-packages':
        value = text.splitlines() if text else []
    elif query in ('shell-account', 'git-probe'):
        if text:
            raise ProtocolError('Unexpected workflow observation output')
        value = None
    elif query == 'wsl-plan':
        value = json.loads(text)
        if (not isinstance(value, dict) or set(value) != {'Arguments', 'Text', 'HostReport'}
                or not isinstance(value['HostReport'], str)
                or any(not isinstance(value[key], list) or any(not isinstance(item, str) for item in value[key])
                       for key in ('Arguments', 'Text'))):
            raise ProtocolError('Invalid WSL preflight observation')
    else:
        value = text
    return {'value': value}
