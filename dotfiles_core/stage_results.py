"""Stage sidecar semantics; platform adapters retain publication and file probes."""
import re

from dotfiles_core.contracts import Contract, ContractError
from dotfiles_core.execution_rules import execution_result

REQUIRED = ('stage', 'status', 'exit_code', 'retry_stage', 'reason', 'report')
ARTIFACTS = ('recovery_journal', 'child_report')
STATUSES = ('running', 'success', 'planned', 'failed', 'deferred', 'interrupted')


def read_stage(text: str) -> list[dict[str, str]]:
    records = Contract.load('stage-result').read(text)
    seen = set()
    for record in records:
        key, value = record['key'], record['value']
        if key not in REQUIRED + ARTIFACTS:
            raise ContractError('Unknown stage result field')
        if key in REQUIRED and key in seen:
            raise ContractError('Duplicate stage result field')
        seen.add(key)
        if key == 'stage' and not re.fullmatch('[a-z][a-z0-9-]*', value):
            raise ContractError('Invalid stage ID')
        if key == 'status' and value not in STATUSES:
            raise ContractError('Invalid stage status')
        if key == 'exit_code' and not re.fullmatch('[0-9]+', value):
            raise ContractError('Invalid stage exit code')
    if not set(REQUIRED) <= seen:
        raise ContractError('Missing stage result field')
    return records


def initial_stage(stage: str, report: str) -> str:
    values = {'stage': stage, 'status': 'running', 'exit_code': '0', 'retry_stage': stage,
              'reason': 'started', 'report': report}
    return Contract.load('stage-result').write([{'key': key, 'value': value} for key, value in values.items()])


def update_stage(text: str, key: str, value: str, append: bool) -> str | None:
    records = read_stage(text)
    if append:
        if key not in ARTIFACTS:
            raise ContractError('Invalid artifact kind')
        if {'key': key, 'value': value} in records:
            return None
    else:
        records = [record for record in records if record['key'] != key]
    records.append({'key': key, 'value': value})
    return Contract.load('stage-result').write(records)


def finish_stage(text: str, code: int, dry: bool, report: str, report_exists: bool) -> str:
    records = read_stage(text)
    stage = next(record['value'] for record in records if record['key'] == 'stage')
    records = [record for record in records if record['key'] in ('stage', *ARTIFACTS)]
    outcome = execution_result(code, dry)
    values = {'status': outcome['Status'], 'exit_code': str(code), 'reason': outcome['Reason'],
              'retry_stage': stage if code else '', 'report': report if report_exists else ''}
    records.extend({'key': key, 'value': value} for key, value in values.items())
    return Contract.load('stage-result').write(records)


OPERATIONS = frozenset(('stage-read', 'stage-init', 'stage-update', 'stage-finish', 'stage-get'))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation in ('stage-read', 'stage-get'):
        records = read_stage(context['text'])
        if operation == 'stage-get':
            values = [record['value'] for record in records if record['key'] == context['key']]
            return values, values
        return records, [Contract.load('stage-result').row(record) for record in records]
    if operation == 'stage-init':
        text = initial_stage(context['stage'], context['report'])
    elif operation == 'stage-update':
        text = update_stage(context['text'], context['key'], context['value'], str(context.get('append', '0')) == '1')
        return {'changed': text is not None, 'document': text}, text.split('\n') if text is not None else []
    elif operation == 'stage-finish':
        text = finish_stage(context['text'], int(context['code']), str(context['dry']) == '1', context['report'], str(context['report_exists']) == '1')
    else:
        raise ContractError('Unknown stage operation')
    return text, text.split('\n')
