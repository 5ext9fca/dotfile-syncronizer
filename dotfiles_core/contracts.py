"""Versioned external envelopes and historical installation-result adaptation."""
from dataclasses import dataclass
from pathlib import Path
import re
from collections.abc import Mapping, Sequence

from dotfiles_core.errors import CoreError

SCHEMA = Path(__file__).resolve().parents[1] / 'contracts/schema'


class ContractError(CoreError):
    pass


@dataclass(frozen=True)
class Contract:
    kind: str
    version: str
    fields: tuple[str, ...]

    @classmethod
    def load(cls, kind: str) -> 'Contract':
        if not re.fullmatch('[a-z][a-z-]*', kind):
            raise ContractError('Invalid contract kind')
        versions = dict(line.split('\t') for line in (SCHEMA / 'types.tsv').read_text().splitlines()
                        if line and not line.startswith('#'))
        if kind not in versions:
            raise ContractError(f'Unknown contract kind: {kind}')
        return cls(kind, versions[kind], tuple((SCHEMA / f'{kind}.fields').read_text().splitlines()))

    def read(self, text: str) -> list[dict[str, str]]:
        # Wire records are separated only by LF. Embedded tabs/CR are invalid,
        # while CRLF documents remain compatible with both platform writers.
        lines = [line.removesuffix('\r') for line in text.rstrip('\n').split('\n')]
        if len(lines) < 2 or lines[0] != f'# dotfiles|{self.kind}|{self.version}':
            raise ContractError(f'Unknown or missing {self.kind} version')
        columns = lines[1].split('|')
        if len(columns) != len(self.fields):
            raise ContractError('Wrong contract field count')
        if len(set(columns)) != len(columns) or set(columns) != set(self.fields):
            raise ContractError('Unknown or duplicate contract field')
        result = []
        for line in lines[2:]:
            cells = line.split('|')
            if len(cells) != len(columns) or re.search('[\r\t]', line):
                raise ContractError('Malformed contract record')
            record = dict(zip(columns, cells, strict=True))
            result.append({field: record[field] for field in self.fields})
        return result

    def row(self, record: Mapping[str, object]) -> str:
        if not isinstance(record, Mapping):
            raise ContractError('Contract record must be an object')
        cells = [str(record.get(field, '') if record.get(field) is not None else '') for field in self.fields]
        if any(re.search('[|\r\n\t]', cell) for cell in cells):
            raise ContractError('Unsupported contract field delimiter')
        return '|'.join(cells)

    def write(self, records: Sequence[Mapping[str, object]]) -> str:
        return '\n'.join([f'# dotfiles|{self.kind}|{self.version}', '|'.join(self.fields),
                          *(self.row(record) for record in records)])

    def from_rows(self, text: str, *, validate_plan: bool = False) -> str:
        document = f'# dotfiles|{self.kind}|{self.version}\n' + '|'.join(self.fields)
        if text:
            document += '\n' + text
        records = self.read(document)
        if validate_plan and self.kind.endswith('-plan'):
            if any(record['schema_version'] != self.version for record in records):
                raise ContractError('Unsupported plan record version')
        return document


def install_result_read(text: str) -> list[dict[str, str]]:
    current = Contract.load('install-result')
    if text.split('\n')[0].removesuffix('\r') == '# dotfiles|install-result|1':
        historical = Contract('install-result', '1', tuple((SCHEMA / 'install-result-v1.fields').read_text().splitlines()))
        # Old reports have no observation evidence; never infer it from reasons.
        return [{field: record.get(field, '') for field in current.fields} for record in historical.read(text)]
    return current.read(text)


def install_result_row(item: Mapping[str, object], status: str, elapsed: str, reason: str, observed: bool = True) -> str:
    record = {'id': item.get('id', ''), 'status': status, 'elapsed_seconds': elapsed,
              'reason': reason, 'selected_method': item.get('method', '')}
    for field in ('detected_method', 'detected_paths', 'decision_reason'):
        record[field] = item.get(field, '') if observed else ''
    return Contract.load('install-result').row(record)


def install_result_show(records: Sequence[Mapping[str, str]]) -> list[str]:
    lines = []
    for item in records:
        if item.get('status') not in ('failed', 'deferred', 'interrupted', 'running', 'skipped', 'blocked'):
            continue
        lines.append(f"  Item {item.get('id', '')}: {item['status']} ({item.get('reason', '')})")
        for field, label in (('selected_method', 'Preferred method'), ('decision_reason', 'Decision')):
            if item.get(field):
                lines.append(f'    {label}: {item[field]}')
        if item.get('detected_method'):
            lines.extend([f"    Matched method: {item['detected_method']}",
                          f"    Matched paths (JSON): {item.get('detected_paths', '')}"])
    return lines


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation == 'install-result-read':
        records = install_result_read(context['text'])
        return records, [Contract.load('install-result').row(record) for record in records]
    if operation == 'install-result-row':
        item = context.get('item')
        if item is None:
            fields = Contract.load('install-plan').fields
            item = dict(zip(fields, context['record'].split('|')))
        value = install_result_row(item, context['status'], str(context['elapsed']), context['reason'], str(context.get('observed', '1')) == '1')
        return value, [value]
    if operation == 'install-result-show':
        records = context.get('records')
        if records is None:
            schema = Contract.load('install-result')
            records = schema.read(schema.from_rows(context['text']))
        lines = install_result_show(records)
        return lines, lines
    schema = Contract.load(context['kind'])
    if operation == 'contract-fields':
        return list(schema.fields), ['|'.join(schema.fields)]
    if operation == 'contract-version':
        return int(schema.version), [schema.version]
    if operation in ('contract-read', 'contract-read-schema'):
        if operation == 'contract-read-schema':
            fields = context['fields']
            schema = Contract(schema.kind, str(context['version']), tuple(fields.split('|') if isinstance(fields, str) else fields))
        records = schema.read(context['text'])
        return records, [schema.row(record) for record in records]
    if operation in ('contract-write', 'contract-validate'):
        if 'records' in context:
            document = schema.write(context['records'])
        else:
            document = schema.from_rows(context['text'], validate_plan=operation == 'contract-validate')
        return document, [] if operation == 'contract-validate' else document.split('\n')
    raise ContractError(f'Unknown contract operation: {operation}')


OPERATIONS = frozenset(('contract-fields', 'contract-version', 'contract-read', 'contract-read-schema',
                        'contract-write', 'contract-validate', 'install-result-read', 'install-result-row', 'install-result-show'))
