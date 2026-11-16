"""Apply scheduling and reports; native adapters own complete file transactions."""
from collections import defaultdict
from pathlib import Path
from typing import Protocol
import os
import time

from dotfiles_core.apply_rules import validate_plan
from dotfiles_core.apply_planning import Paths
from dotfiles_core.contracts import Contract
from dotfiles_core.errors import AdapterError, CoreError, ProtocolError
from dotfiles_core.native_apply import native_filesystem
from dotfiles_core.stage_results import initial_stage, read_stage, update_stage, finish_stage
from dotfiles_core.workflow_packages import boolean



class Operations(Protocol):
    def validate_outputs(self, rows: list[dict], results: str, metadata: str) -> None: ...
    def exists(self, path: str) -> bool: ...
    def is_file(self, path: str) -> bool: ...
    def read(self, path: str) -> str: ...
    def publish(self, path: str, text: str, mode: str = 'replace') -> None: ...
    def start(self, session: str) -> None: ...
    def transaction(self, row: dict, journal: str, sequence: int) -> None: ...
    def preview(self, row: dict) -> None: ...


def summaries(rows: list[dict], style: str) -> list[str]:
    groups = defaultdict(lambda: defaultdict(int))
    for row in rows:
        counts = groups[row['component']]
        counts['elapsed'] += int(row['elapsed_seconds'])
        status = row['status']
        if status in ('failed', 'blocked', 'skipped'):
            counts[status] += 1
        elif style == 'unix' and row['action'] == 'mkdir':
            counts['directories'] += 1
        elif row['reason'] == 'replace':
            counts['replaced'] += 1
        elif style == 'unix' or (row['action'] != 'mkdir' and row['reason'] == 'new'):
            counts['new'] += 1
    keys = ['new', 'replaced', 'skipped'] + (['directories'] if style == 'unix' else []) + ['failed', 'blocked']
    return [f'{name}: ' + ' '.join(f'{key}={groups[name][key]}' for key in keys)
            + f' elapsed={groups[name]["elapsed"]}s' for name in sorted(groups)]


def execute(rows: list[dict], session: str, dry: bool, results: str, metadata: str,
            style: str, native: Operations, *, clock=time.monotonic, emit=lambda text: print(text, flush=True)) -> int:
    validate_plan(rows, style)
    native.validate_outputs(rows, results, metadata)
    if metadata:
        if native.exists(metadata):
            read_stage(native.read(metadata))
        else:
            native.publish(metadata, initial_stage('apply', results), 'create')
    journal = os.path.join(session, 'journal.tsv' if style == 'unix' else 'journal.jsonl')
    if not dry and rows:
        native.start(session)
        if metadata:
            text = update_stage(native.read(metadata), 'recovery_journal', journal, True)
            if text is not None:
                native.publish(metadata, text)
        emit(f'Recovery journal: {journal}')
    failed = 0
    report = []
    for sequence, row in enumerate(rows, 1):
        started = clock()
        if row['action'] == 'skip':
            status = 'skipped'
        elif failed:
            status = 'blocked'
        elif dry:
            status = 'planned'
            native.preview(row)
        else:
            try:
                native.transaction(row, journal, sequence)
                status = 'success'
            except (AdapterError, ProtocolError) as exc:
                status = 'failed'
                failed = getattr(exc, 'exit_code', 65) if style == 'unix' else 1
        elapsed = clock() - started
        elapsed = int(elapsed) if style == 'unix' else round(elapsed)
        report.append({key: row[key] for key in ('component', 'action', 'target', 'backup', 'reason')} |
                      {'status': status, 'elapsed_seconds': str(elapsed)})
        suffix = f'; {elapsed}s' if style == 'unix' else ''
        emit(f'{row["target"]}: {status} ({row["reason"]}{suffix})')
    if results:
        native.publish(results, Contract.load('apply-result').write(report))
    for line in summaries(report, style):
        emit(line)
    if metadata:
        native.publish(metadata, finish_stage(native.read(metadata), failed, dry, results,
                                             bool(results) and native.is_file(results)))
    return failed


class NativeExecution:
    def __init__(self, style: str, shell: str):
        self.style = style
        self.fs = native_filesystem(style, shell)
        self.adapter = self.fs.adapter
        command = self.adapter.operations['apply-query']
        for operation in ('apply-effect', 'publish-report'):
            self.adapter.operations[operation] = command

    def effect(self, action: str, path: str = '', row: dict | None = None, sequence: int = 0):
        result = self.adapter.invoke('apply-effect', {'action': action, 'path': path,
                                     'row': row or {}, 'sequence': sequence})
        if result.data:
            raise ProtocolError('Malformed native apply effect result')

    def start(self, session):
        self.effect('start', session)

    def transaction(self, row, journal, sequence):
        self.effect('transaction', journal, row, sequence)

    def preview(self, row):
        self.effect('preview', row=row)

    def publish(self, path, text, mode='replace'):
        result = self.adapter.invoke('publish-report', {'path': path, 'text': text, 'mode': mode})
        if result.data:
            raise ProtocolError('Malformed native publication result')

    def exists(self, path):
        return self.fs.value('exists', path, boolean=True)

    def is_file(self, path):
        return self.fs.value('file', path, boolean=True)

    def read(self, path):
        return Path(path).read_text(encoding='utf-8-sig')

    def validate_outputs(self, rows, results, metadata):
        for output in (results, metadata):
            if not output:
                continue
            if any(char in output for char in '|\t\r\n\0'):
                raise CoreError('Unsupported result path')
            absolute = os.path.abspath(output)
            parent = os.path.dirname(absolute)
            entry = self.fs.entry(output)
            parent_entry = self.fs.entry(parent)
            if self.style == 'unix':
                valid = self.fs.value('directory', parent, boolean=True) and parent_entry.writable
                valid = valid and not self.fs.value('directory', output, boolean=True) and entry.kind != 'link'
                valid = valid and (not self.exists(output) or entry.writable)
                absolute = os.path.join(self.fs.value('physical-directory', parent), os.path.basename(output)) if valid else absolute
            else:
                valid = parent_entry.kind == 'directory' and entry.kind not in ('directory', 'link')
                valid = valid and not self.fs.value('readonly', output, boolean=True)
            if not valid:
                raise CoreError('Invalid results destination')
            key = absolute.casefold() if self.style == 'windows' else absolute
            exists = self.exists(output)
            identity = self.fs.identity(output) if exists else ''
            for row in rows:
                for path in (row['source'], row['target']):
                    if not path:
                        continue
                    if Paths(windows=os.name == 'nt', case_insensitive=self.style == 'windows').overlaps(key, path):
                        raise CoreError('Results overlap a deployment path')
                    if exists and self.exists(path) and identity == self.fs.identity(path):
                        raise CoreError('Results alias a deployment file')
        if results and metadata:
            equal = (os.path.abspath(results).casefold() == os.path.abspath(metadata).casefold()
                     if self.style == 'windows' else results == metadata)
            alias = self.exists(results) and self.exists(metadata) and self.fs.identity(results) == self.fs.identity(metadata)
            if equal or alias:
                raise CoreError('Stage result overlaps detail report')


OPERATIONS = frozenset(('apply-execute-native',))


def request(operation: str, context: dict) -> tuple[object, list[str]]:
    if operation not in OPERATIONS:
        raise ProtocolError('Unknown apply execution request')
    schema = Contract.load('apply-plan')
    text = schema.write(context['records']) if 'records' in context else context['text']
    if not text.startswith('# dotfiles|'):
        text = schema.from_rows(text)
    rows = schema.read(text)
    style = context['style']
    dry = boolean(context['dry'])
    native = NativeExecution(style, context['native_shell'])
    code = execute(rows, context['session'], dry, context.get('results', ''), context.get('metadata', ''), style, native)
    if code:
        raise AdapterError('Apply execution failed', code)
    return None, []
