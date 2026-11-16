"""Historical workflow summaries and manual resume decisions.

Summary formats remain platform-specific. Sidecars are authoritative for status
and artifacts; old reports never authorize skipping an installation observation.
"""
import json
from pathlib import Path
import re
import shlex

from dotfiles_core.contracts import Contract, ContractError, install_result_read, install_result_show
from dotfiles_core.stage_results import read_stage, ARTIFACTS

STATUSES = ('pending', 'running', 'success', 'planned', 'skipped', 'failed', 'blocked', 'deferred', 'interrupted')
UNFINISHED = ('failed', 'deferred', 'interrupted', 'running', 'blocked', 'pending')


class ResumeError(ContractError):
    exit_code = 2


def read_text(path: Path) -> str:
    return path.read_text(encoding='utf-8-sig')


def read_request(session: Path) -> dict[str, str]:
    text = read_text(session / 'request.tsv')
    if text.startswith('# dotfiles|workflow-request|2\n'):
        text = text.replace('# dotfiles|workflow-request|2', '# dotfiles|workflow-request|3', 1)
    records = Contract.load('workflow-request').read(text)
    if len(records) != 1:
        raise ContractError('Expected one workflow request')
    record = records[0]
    if (not re.fullmatch(r'linux\.(apt|dnf|pacman|none)|macos|windows', record['platform'])
            or not re.fullmatch('[a-z][a-z0-9-]*', record['profile'])
            or record['china_mirrors'] not in ('0', '1') or record['dry_run'] not in ('0', '1')):
        raise ContractError('Invalid workflow request')
    stages = record['selected_stages'].split(',')
    if len(stages) != len(set(stages)) or any(not re.fullmatch('[a-z][a-z0-9-]*', stage) for stage in stages):
        raise ContractError('Invalid selected stages')
    return record


def read_summary(session: Path, style: str) -> list[dict]:
    if style == 'unix':
        records = Contract.load('workflow-summary').read('# dotfiles|workflow-summary|1\n' + read_text(session / 'workflow.tsv'))
    elif style == 'windows':
        records = json.loads(read_text(session / 'workflow.json'))
        if records is None:
            records = []
        if isinstance(records, dict):
            records = [records]
        if not isinstance(records, list):
            raise ContractError('Invalid workflow summary')
    else:
        raise ContractError('Unknown workflow summary style')
    seen = set()
    for record in records:
        if (not isinstance(record, dict) or str(record.get('schema_version')) != '1'
                or not re.fullmatch('[a-z][a-z0-9-]*', str(record.get('stage', '')))
                or record['stage'] in seen or record.get('status') not in STATUSES
                or not re.fullmatch('-?[0-9]+' if style == 'windows' else '[0-9]+', str(record.get('exit_code', '')))):
            raise ContractError('Invalid workflow summary')
        seen.add(record['stage'])
    return records


def review(session: Path, style: str) -> list[dict]:
    records = read_summary(session, style)
    for record in records:
        metadata = session / (record['stage'] + '.result')
        if metadata.exists():
            values = {item['key']: item['value'] for item in read_stage(read_text(metadata)) if item['key'] not in ARTIFACTS}
            if values['stage'] != record['stage']:
                raise ContractError('Stage result identity mismatch')
            if record['status'] != values['status'] or not record.get('reason'):
                record['reason'] = values['reason']
            record.update(status=values['status'], report=values['report'],
                          exit_code=int(values['exit_code']) if style == 'windows' else values['exit_code'])
    if (session / 'request.tsv').exists():
        request = read_request(session)
        seen = {record['stage'] for record in records}
        for stage in request['selected_stages'].split(','):
            if stage in seen:
                continue
            record = {'stage': stage, 'status': 'pending', 'exit_code': 0 if style == 'windows' else '0',
                      'reason': 'not-started', 'log': '', 'report': ''}
            if style == 'unix':
                record = {**{field: '' for field in Contract.load('workflow-summary').fields}, **record,
                          'profile': request['profile'], 'elapsed_seconds': '0', 'schema_version': '1', 'retry_stage': stage}
            records.append(record)
    return records


def resume(session: Path, platform: str, profile: str, style: str,
           only: str = '', start: str = '', mirrors_explicit: bool = False, profile_explicit: bool = False) -> dict:
    if only or start or mirrors_explicit or profile_explicit:
        raise ResumeError('Resume cannot be combined with profile, stage or mirror selectors')
    session = session.resolve(strict=True)
    try:
        if not read_text(session / 'request.tsv').startswith('# dotfiles|workflow-request|3\n'):
            raise ResumeError('Legacy workflow sessions are read-only; start a new installation run')
        saved = read_request(session)
    except ResumeError:
        raise
    except (OSError, ContractError) as exc:
        raise ResumeError('Session has no valid resume request; use --from-stage manually') from exc
    if saved['profile'] == 'snapshot':
        raise ResumeError('Snapshot sessions require rerunning snapshot restore with the archive')
    if saved['platform'] != platform or saved['dry_run'] != '0':
        raise ResumeError('Resume requires a real session on the same platform/profile')
    records = {record['stage']: record for record in review(session, style)}
    remaining = []
    failed = False
    for stage in saved['selected_stages'].split(','):
        failed = failed or records.get(stage, {}).get('status') != 'success'
        if failed:
            remaining.append(stage)
    if not remaining:
        raise ResumeError('Session already completed; nothing to resume')
    return {'session': str(session), 'profile': saved['profile'], 'china_mirrors': saved['china_mirrors'], 'resume_stages': remaining}


def filter_stages(stages: list[dict], selected: list[str]) -> list[dict]:
    names = {stage['Id'] for stage in stages}
    for name in selected:
        if name not in names:
            raise ResumeError(f'Resume stage no longer exists: {name}')
    return [dict(stage) if stage['Id'] in selected else {**stage, 'Enabled': False, 'Reason': 'resume-selection'} for stage in stages]


def request_document(platform: str, profile: str, mirrors: str, selected: list[str], parent: str, dry: str) -> str | None:
    if not selected:
        return None
    record = {'platform': platform, 'profile': profile, 'china_mirrors': mirrors,
              'selected_stages': ','.join(selected), 'resume_parent': parent, 'dry_run': dry}
    return Contract.load('workflow-request').write([record])


def show_status(session: Path, style: str) -> list[str]:
    lines = []
    retry = ''
    for record in review(session, style):
        stage, status = record['stage'], record['status']
        lines.append(f"{stage}: {status} (exit={record['exit_code']}, {record.get('reason', '')})")
        if not retry and status in UNFINISHED:
            retry = stage
        if status == 'deferred':
            lines.append('  Action: complete the manual prerequisite, then retry.')
        if status == 'running':
            lines.append('  Action: incomplete record; verify the previous run has stopped before retrying.')
        if record.get('log'):
            lines.append(f"  Log: {record['log']}")
        if record.get('report'):
            lines.append(f"  Detail report: {record['report']}")
            report = Path(record['report'])
            if report.is_file():
                text = read_text(report)
                header = text.split('\n', 1)[0].removesuffix('\r').split('|')
                kind = header[1] if len(header) > 1 else ''
                if kind == 'install-result':
                    lines.extend(install_result_show(install_result_read(text)))
                elif kind in ('apply-result', 'git-result'):
                    details = Contract.load(kind).read(text)
                    for detail in details:
                        if style == 'unix' and kind == 'apply-result' and detail['status'] in ('failed', 'deferred', 'interrupted'):
                            lines.append(f"  Component {detail['component']}: {detail['status']} ({detail['reason']}), target={detail['target']}")
                        elif style == 'windows' and detail['status'] in ('failed', 'deferred', 'interrupted', 'running'):
                            identity = detail['component'] if kind == 'apply-result' else detail['key']
                            lines.append(f"  Item {identity}: {detail['status']} ({detail.get('reason', '')})")
        metadata = session / (stage + '.result')
        if metadata.exists():
            for entry in read_stage(read_text(metadata)):
                if entry['key'] == 'recovery_journal':
                    lines.append(f"  Recovery journal (inspect if configuration recovery is needed): {entry['value']}")
                if entry['key'] == 'child_report':
                    lines.append(f"  Child report: {entry['value']}")
        else:
            if record.get('recovery_journal'):
                lines.append(f"  Legacy recovery references: {record['recovery_journal']}")
            if record.get('child_report'):
                lines.append(f"  Legacy child reports: {record['child_report']}")
    if retry:
        if (session / 'request.tsv').exists():
            request = read_request(session)
            if request['profile'] == 'snapshot':
                lines.append('Retry after resolving the cause: rerun snapshot restore with the original archive (use configuration-only for an apply session); installation resume is not supported.')
            elif not read_text(session / 'request.tsv').startswith('# dotfiles|workflow-request|3\n'):
                lines.append('Legacy workflow session is read-only; start a new installation run. Guarded journal recovery remains available.')
            elif request['dry_run'] == '1':
                option = '--dry-run' if style == 'unix' else '-DryRun'
                lines.append(f'Recheck after resolving the cause: rerun the original command with {option} and the same stage selection and mirror options (dry-run sessions cannot be resumed).')
            elif style == 'unix':
                lines.append(f"Resume after resolving the cause: ./install/{request['platform'].split('.')[0]}.sh --resume {shlex.quote(str(session))}")
            else:
                lines.append("Resume after resolving the cause: ./install/windows.ps1 -Resume '" + str(session).replace("'", "''") + "'")
        else:
            lines.append('Legacy session has no saved selection; start a new installation run or restore a configuration snapshot. Guarded journal recovery remains available.')
    return lines


OPERATIONS = frozenset(('workflow-status', 'workflow-request-read'))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation == 'workflow-request-read':
        record = read_request(Path(context['session']))
        return record, [Contract.load('workflow-request').row(record)]
    if operation != 'workflow-status':
        raise ContractError('Unknown workflow review operation')
    lines = show_status(Path(context['session']), context.get('style', 'unix'))
    return lines, lines
