"""Application payload declarations and portable selection rules."""
from dataclasses import dataclass, asdict
from pathlib import Path
import re

from dotfiles_core.errors import CoreError
from dotfiles_core.install_config import ROOT


class ApplyConfigError(CoreError):
    pass


@dataclass(frozen=True)
class ApplyItem:
    id: str
    source: str
    target_root: str
    target: str
    method: str
    exclude: str = ''
    condition: str = ''
    renderer: str = ''

    def line(self) -> str:
        return '|'.join((self.id, self.source, self.target_root, self.target, self.method,
                         self.exclude, self.condition, self.renderer))


def relative(path: str) -> bool:
    return bool(path and not re.search(r'[:\\|\t\r\n]', path) and all(part not in ('', '.', '..') for part in path.split('/')))


def excluded(path: str, exclusions: str) -> bool:
    return any(path == entry or path.startswith(entry + '/') for entry in exclusions.split(';') if entry)


def read_items(directory: Path, platform: str) -> list[ApplyItem]:
    rules = {}
    for line in (ROOT / 'apply/schema/fields.tsv').read_text(encoding='utf-8').splitlines():
        if line and not line.startswith('#'):
            key, pattern, required = line.split('\t')
            rules[key] = (pattern, required == 'yes')
    files = sorted(directory.glob('*.conf'))
    if not files:
        raise ApplyConfigError('No apply item configurations found')
    items = []
    for path in files:
        if not path.is_file() or path.stat().st_size == 0 or not re.fullmatch('[a-z0-9][a-z0-9-]*', path.stem):
            raise ApplyConfigError(f'Invalid component: {path}')
        sections = {}
        section = None
        for number, raw in enumerate(path.read_text(encoding='utf-8-sig').splitlines(), 1):
            line = raw.strip(' \t\r')
            if not line or line.startswith('#'):
                continue
            if line.startswith('['):
                if line not in ('[unix]', '[windows]'):
                    raise ApplyConfigError(f'Unknown platform ({path}:{number})')
                section = line[1:-1]
                if section in sections:
                    raise ApplyConfigError(f'Duplicate platform section ({path}:{number})')
                sections[section] = {}
            else:
                if section is None or '=' not in line:
                    raise ApplyConfigError(f'Expected key=value in a section ({path}:{number})')
                key, value = line.split('=', 1)
                if key not in rules or key in sections[section] or re.search('[|\t]', value):
                    raise ApplyConfigError(f'Unknown/duplicate field or unsupported value ({path}:{number})')
                sections[section][key] = value
        for name, values in sections.items():
            for key, (pattern, required) in rules.items():
                value = values.get(key, '')
                if required and not value:
                    raise ApplyConfigError(f'Missing {key}: {path}')
                if value and not re.fullmatch(pattern, value):
                    raise ApplyConfigError(f'Invalid {key}: {path}')
            item = ApplyItem(id=path.stem, **values)
            if not relative(item.source) or not relative(item.target):
                raise ApplyConfigError('Source and target must be safe relative paths')
            if item.exclude and any(not relative(entry) for entry in item.exclude.split(';')):
                raise ApplyConfigError('Invalid exclusion')
            if name == 'unix' and item.target_root not in ('home', 'config_home'):
                raise ApplyConfigError('Unix requires home or config_home')
            if name == 'windows' and (item.target_root not in ('home', 'app_data', 'local_app_data') or item.method != 'copy'):
                raise ApplyConfigError('Windows requires home, app_data or local_app_data and copy')
            if item.renderer:
                raise ApplyConfigError('Configuration rendering was removed; capture real files')
            if name == 'windows' and item.condition:
                raise ApplyConfigError('Conditions are Unix-only')
            if name == platform:
                items.append(item)
    return items


def validate_plan(records: list[dict[str, str]], style: str) -> None:
    from dotfiles_core.contracts import Contract
    version = Contract.load('apply-plan').version
    actions = {'mkdir', 'copy', 'skip'}
    if style == 'unix':
        actions.add('hardlink')
    elif style != 'windows':
        raise ApplyConfigError('Unknown apply platform')
    targets = set()
    for record in records:
        if str(record.get('schema_version')) != version or record.get('action') not in actions:
            raise ApplyConfigError('Malformed apply plan record')
        if style == 'unix' and record.get('reason') != 'excluded':
            target = record.get('target', '')
            if target in targets:
                raise ApplyConfigError('Overlapping deployment/mirror targets')
            targets.add(target)


OPERATIONS = frozenset(('apply-items', 'apply-validate'))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation == 'apply-validate':
        from dotfiles_core.contracts import Contract
        schema = Contract.load('apply-plan')
        if 'records' in context:
            records = schema.read(schema.write(context['records']))
        else:
            records = schema.read(schema.from_rows(context['text']))
        validate_plan(records, context['style'])
        return None, []
    if operation != 'apply-items':
        raise ApplyConfigError('Unknown apply declaration operation')
    items = read_items(Path(context['directory']), context['platform'])
    return [asdict(item) for item in items], [item.line() for item in items]
