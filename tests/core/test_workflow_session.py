from dataclasses import replace
import json
from pathlib import Path
import tempfile
import unittest

from dotfiles_core.stage_results import update_stage
from dotfiles_core.workflow_review import read_summary, resume
from dotfiles_core.workflow_session import Session, Stage, StageExecution, run


class NativeOperations:
    def __init__(self):
        self.calls = []
        self.publications = []
        self.code = 0
        self.corrupt = False

    def publish(self, path, text, mode='replace'):
        # Independent native-publication stand-in: preserve create semantics.
        with path.open('x' if mode == 'create' else 'w', encoding='utf-8') as stream:
            stream.write(text)
        self.publications.append((path, text, mode))

    def execute(self, action, report, metadata, log):
        summaries = [(path, text) for path, text, _ in self.publications
                     if path.name in ('workflow.tsv', 'workflow.json')]
        if summaries:
            path, text = summaries[-1]
            if path.suffix == '.json':
                assert json.loads(text)[-1]['status'] == 'running'
            else:
                assert '|running|' in text.splitlines()[-1]
        assert metadata.exists()
        self.calls.append(action)
        log.write_text('native output\n', encoding='utf-8')
        report.write_text('detail\n', encoding='utf-8')
        text = metadata.read_text()
        text = update_stage(text, 'child_report', 'child report 中文', True)
        text = update_stage(text, 'recovery_journal', 'journal,one', True)
        metadata.write_text('broken' if self.corrupt else text, encoding='utf-8')
        return StageExecution(self.code, 'native failure' if self.code else '')


class WorkflowSessionTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='workflow session 中文 ')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.context = self.root / 'context'
        self.context.mkdir()
        self.session = Session('test', self.root / 'session', 'test', 'macos', 'unix', False, True,
                               (Stage('packages', True, 'selected', 'packages'),
                                Stage('configuration', True, 'selected', 'configuration'),
                                Stage('mirrors', False, 'disabled', 'mirrors')),
                               context_directory=self.context)
        self.native = NativeOperations()

    def test_running_snapshot_precedes_execution_and_artifacts_survive(self):
        result = run(self.session, self.native, emit=lambda _: None)
        self.assertEqual(result.exit_code, 0)
        self.assertEqual(self.native.calls, ['packages', 'configuration'])
        self.assertEqual([row['status'] for row in result.rows], ['success', 'success', 'skipped'])
        self.assertEqual(result.rows[0]['child_report'], 'child report 中文')
        self.assertEqual(result.rows[0]['recovery_journal'], 'journal,one')
        snapshots = [text for path, text, _ in self.native.publications if path.name == 'workflow.tsv']
        self.assertIn('|running|', snapshots[1])
        self.assertNotIn('|running|', snapshots[-1])
        rows = read_summary(self.session.path, 'unix')
        self.assertEqual(rows[0]['status'], 'success')
        events = (self.session.path / 'events.tsv').read_text()
        self.assertEqual(events.count('|running|'), 2)
        self.assertIn('|selected|', events)

    def test_failure_blocks_enabled_stages_but_keeps_disabled_reason(self):
        self.native.code = 130
        result = run(self.session, self.native, emit=lambda _: None)
        self.assertEqual(result.exit_code, 130)
        self.assertEqual(self.native.calls, ['packages'])
        self.assertEqual([row['status'] for row in result.rows], ['interrupted', 'blocked', 'skipped'])
        self.assertEqual([row['reason'] for row in result.rows], ['signal-int', 'previous-stage-failed', 'disabled'])
        self.assertEqual([row['retry_stage'] for row in result.rows], ['packages'] * 3)
        saved = resume(self.session.path, 'macos', 'test', 'unix')
        self.assertEqual(saved['resume_stages'], ['packages', 'configuration'])

    def test_windows_exception_reason_json_and_elapsed_rounding(self):
        session = replace(self.session, style='windows', platform='windows')
        self.native.code = 23
        ticks = iter([0, 1.6, 2, 2.1, 3, 3.1])
        result = run(session, self.native, emit=lambda _: None, clock=lambda: next(ticks))
        self.assertEqual(result.rows[0]['reason'], 'native failure')
        self.assertEqual(result.rows[0]['elapsed_seconds'], 2)
        self.assertEqual(json.loads(Path(result.summary).read_text())[0]['exit_code'], 23)
        self.assertEqual(read_summary(session.path, 'windows')[1]['status'], 'blocked')
        self.assertFalse((session.path / 'events.tsv').exists())

    def test_windows_negative_code_preserves_existing_sidecar_rejection(self):
        # The existing sidecar contract permits unsigned decimal codes only.
        # A native signed failure must reach that policy, producing a failed
        # summary and blocked stages instead of abandoning a running snapshot.
        self.native.code = -1978335212
        result = run(replace(self.session, style='windows', platform='windows'), self.native, emit=lambda _: None)
        self.assertEqual(result.exit_code, 65)
        self.assertEqual(result.rows[0]['reason'], 'invalid-stage-result')
        self.assertEqual(result.rows[1]['status'], 'blocked')
        self.assertEqual(json.loads(Path(result.summary).read_text())[0]['exit_code'], 65)

    def test_invalid_sidecar_fails_and_blocks_following_stages(self):
        self.native.corrupt = True
        result = run(self.session, self.native, emit=lambda _: None)
        self.assertEqual(result.exit_code, 65)
        self.assertEqual(self.native.calls, ['packages'])
        self.assertEqual(result.rows[1]['status'], 'blocked')
        self.assertEqual(result.rows[0]['child_report'], '')

    def test_existing_explicit_output_prevents_stage_mutation(self):
        output = self.root / 'output'
        output.write_text('keep')
        with self.assertRaises(FileExistsError):
            run(replace(self.session, results=str(output)), self.native, emit=lambda _: None)
        self.assertEqual(self.native.calls, [])
        self.assertEqual(output.read_text(), 'keep')

    def test_abrupt_native_failure_leaves_running_snapshot(self):
        def interrupted(*args):
            raise KeyboardInterrupt()
        self.native.execute = interrupted
        with self.assertRaises(KeyboardInterrupt):
            run(self.session, self.native, emit=lambda _: None)
        rows = read_summary(self.session.path, 'unix')
        self.assertEqual([row['status'] for row in rows], ['running'])
        self.assertEqual(rows[0]['retry_stage'], 'packages')
        self.assertTrue((self.session.path / 'packages.result').exists())

    def test_initial_sidecar_never_replaces_an_unexpected_file(self):
        publish = self.native.publish

        def conflicting_publication(path, text, mode='replace'):
            if path.name == 'packages.result':
                path.write_text('unexpected existing file')
            publish(path, text, mode)

        self.native.publish = conflicting_publication
        with self.assertRaises(FileExistsError):
            run(self.session, self.native, emit=lambda _: None)
        self.assertEqual(self.native.calls, [])
        self.assertEqual((self.session.path / 'packages.result').read_text(), 'unexpected existing file')

    def test_dry_run_with_explicit_results_is_persistent(self):
        output = self.root / 'results.tsv'
        result = run(replace(self.session, dry=True, results=str(output)), self.native, emit=lambda _: None)
        self.assertTrue(result.summary)
        self.assertEqual(output.read_text(), Path(result.summary).read_text())
        self.assertEqual(result.rows[0]['status'], 'planned')
        self.assertTrue(Path(result.rows[0]['log']).is_file())
        self.assertEqual([mode for path, _, mode in self.native.publications if path == output][0], 'create')

    def test_dry_session_clears_ephemeral_references_and_windows_cleans_up(self):
        for style in ('unix', 'windows'):
            native = NativeOperations()
            session = replace(self.session, style=style, dry=True)
            result = run(session, native, emit=lambda _: None)
            self.assertEqual(result.summary, '')
            self.assertEqual(result.rows[0]['status'], 'planned')
            self.assertEqual(result.rows[0]['report'], '')
            self.assertEqual(result.rows[0]['log'], '')
            self.assertEqual(result.rows[0]['child_report'], 'child report 中文')
            directory = native.publications[0][0].parent
            self.assertEqual(directory.exists(), style == 'unix')


if __name__ == '__main__':
    unittest.main()
