"""Mirror declarations and text transformations, independent of host paths."""
from collections.abc import Mapping
from pathlib import Path
import re

from dotfiles_core.errors import CoreError

KEYS = ('rust_dist rust_update pypi cargo_index npm go_proxy go_sumdb brew_git brew_core '
        'brew_cask brew_bottles brew_api ubuntu ubuntu_ports debian debian_security fedora arch manjaro').split()


class MirrorError(CoreError):
    pass


def read_config(text: str) -> dict[str, str]:
    result = {}
    for raw in text.split('\n'):
        line = raw.removesuffix('\r')
        if not line or line.startswith('#'):
            continue
        key, separator, value = line.partition('=')
        if (not separator or key not in KEYS or key in result or not value
                or re.search(r'''[|\t '"\\]''', value)):
            raise MirrorError('Invalid mirror configuration')
        if key == 'go_sumdb':
            valid = re.fullmatch('[a-zA-Z0-9.-]+', value)
        else:
            valid = re.match(r'(https?://|sparse\+https://)', value)
        if not valid:
            raise MirrorError('Invalid mirror configuration')
        result[key] = value
    if set(result) != set(KEYS):
        raise MirrorError('Incomplete mirror configuration')
    return {key: result[key] for key in KEYS}


def config_text(config: Mapping[str, str]) -> str:
    return ''.join(f'{key}={config[key]}\n' for key in KEYS)


def environment(config: Mapping[str, str], schema: Path) -> list[tuple[str, str]]:
    result = []
    for line in schema.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        variable, key = line.split('\t')
        if not re.fullmatch('[A-Z][A-Z0-9_]*', variable) or not config.get(key):
            raise MirrorError('Invalid mirror environment mapping')
        result.append((variable, config[key]))
    return result


def replace_endpoint(text: str, old: str, new: str) -> str:
    if not old or old == new:
        return text
    result = []
    while old in text:
        start = text.index(old)
        end = start + len(old)
        tail = text[end:end + 1]
        boundary = not tail or tail in '/"' or tail.isspace()
        result.extend((text[:start], new if boundary else old))
        text = text[end:]
    return ''.join(result) + text


def render(kind: str, mode: str, text: str, current: Mapping[str, str],
           previous: Mapping[str, str], legacy: Mapping[str, str]) -> str:
    if kind not in ('cargo', 'npm', 'go', 'apt', 'dnf') or mode not in ('apply', 'initialize'):
        raise MirrorError('Invalid mirror renderer or mode')
    def endpoint(line: str, key: str) -> str:
        if mode == 'apply':
            line = replace_endpoint(line, legacy.get(key, ''), current[key])
            line = replace_endpoint(line, previous.get(key, ''), current[key])
        return line
    section = ''
    found = set()
    result = []
    # AWK preserves CR characters in payload lines and terminates every record
    # with LF, including an unterminated final input record.
    lines = text.split('\n')
    if lines[-1] == '':
        lines.pop()
    for line in lines:
        if kind == 'cargo':
            if line.startswith('['):
                section = line
            if section == '[source.rsproxy-sparse]' and re.match(r'^[ \t]*registry[ \t]*=', line):
                line = f'registry = "{current["cargo_index"]}"'
            if section == '[registries.rsproxy]' and re.match(r'^[ \t]*index[ \t]*=', line):
                line = f'index = "{current["cargo_index"]}"'
        elif kind == 'npm':
            if re.match(r'^[ \t]*registry[ \t]*=', line):
                line = 'registry=' + current['npm']
                found.add('registry')
        elif kind == 'go':
            for variable, key in (('GOPROXY', 'go_proxy'), ('GOSUMDB', 'go_sumdb')):
                if line.startswith(variable + '='):
                    found.add(variable)
                    if mode == 'apply' and line in (variable + '=' + previous.get(key, ''), variable + '=' + legacy.get(key, '')):
                        line = variable + '=' + current[key]
        elif kind == 'apt':
            sources = [('archive.ubuntu.com/ubuntu', 'ubuntu'), ('security.ubuntu.com/ubuntu', 'ubuntu'),
                       ('ports.ubuntu.com/ubuntu-ports', 'ubuntu_ports'),
                       ('deb.debian.org/debian-security', 'debian_security'),
                       ('security.debian.org/debian-security', 'debian_security'),
                       ('security.debian.org', 'debian_security'), ('deb.debian.org/debian', 'debian'),
                       ('ftp.debian.org/debian', 'debian')]
            for source, key in sources:
                for scheme in ('http://', 'https://'):
                    line = replace_endpoint(line, scheme + source, current[key])
            for key in ('debian_security', 'debian', 'ubuntu_ports', 'ubuntu'):
                line = endpoint(line, key)
        elif kind == 'dnf':
            if re.search(r'^metalink=.*mirrors.fedoraproject.org/metalink', line):
                line = '#' + line
            match = re.match(r'^#baseurl=https?://[^/]+/pub/fedora/linux', line)
            if match:
                line = 'baseurl=' + current['fedora'] + line[match.end():]
            line = endpoint(line, 'fedora')
        result.append(line)
    if kind == 'npm' and 'registry' not in found:
        result.append('registry=' + current['npm'])
    if kind == 'go':
        for variable, key in (('GOPROXY', 'go_proxy'), ('GOSUMDB', 'go_sumdb')):
            if variable not in found:
                result.append(variable + '=' + current[key])
    return ''.join(line + '\n' for line in result)
