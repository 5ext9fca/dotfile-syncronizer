import json
from pathlib import Path
import tempfile
import unittest

from dotfiles_core.contracts import Contract, ContractError
from dotfiles_core.stage_results import initial_stage, finish_stage, update_stage
from dotfiles_core.workflow_review import read_request, review, resume, ResumeError, filter_stages, request_document, show_status, request


class WorkflowReviewTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='dotfiles review ')
        self.addCleanup(self.directory.cleanup)
        self.session = Path(self.directory.name)

    def save(self, style, statuses=('success', 'failed')):
        schema = Contract.load('workflow-summary')
        records = []
        for stage, status in zip(('packages', 'configuration'), statuses):
            row = {field: '' for field in schema.fields}
            row.update(session='old', profile='test', stage=stage, status=status, exit_code=0 if status == 'success' else 23,
                       elapsed_seconds=0, reason='command-failed' if status != 'success' else 'completed', schema_version=1)
            records.append(row)
        if style == 'unix':
            text = '\n'.join(schema.write(records).split('\n')[1:])
            (self.session / 'workflow.tsv').write_text(text)
        else:
            (self.session / 'workflow.json').write_text(json.dumps(records))
        platform = 'macos' if style == 'unix' else 'windows'
        (self.session / 'request.tsv').write_text(request_document(platform, 'test', '0', ['packages', 'configuration', 'shell'], '', '0'))
        return platform

    def test_resume_keeps_remaining_selection_and_mirrors(self):
        for style in ('unix', 'windows'):
            with self.subTest(style=style):
                platform = self.save(style)
                state = resume(self.session, platform, 'test', style)
                self.assertEqual(state['resume_stages'], ['configuration', 'shell'])
                self.assertEqual(state['china_mirrors'], '0')
                self.assertEqual(review(self.session, style)[-1]['status'], 'pending')
                for kwargs in ({'only': 'configuration'}, {'start': 'packages'}, {'mirrors_explicit': True}, {'profile_explicit': True}):
                    with self.assertRaises(ResumeError):
                        resume(self.session, platform, 'test', style, **kwargs)
                self.assertEqual(resume(self.session, platform, 'other', style)['profile'], 'test')

    def test_sidecar_authority_and_artifacts(self):
        for style in ('unix', 'windows'):
            with self.subTest(style=style):
                platform = self.save(style)
                text = update_stage(initial_stage('configuration', ''), 'recovery_journal', 'path,with comma', True)
                text = finish_stage(text, 130, False, 'absent-report', False)
                (self.session / 'configuration.result').write_text(text)
                row = review(self.session, style)[1]
                self.assertEqual(row['status'], 'interrupted')
                self.assertEqual(str(row['exit_code']), '130')
                self.assertEqual(row['reason'], 'signal-int')
                shown = '\n'.join(show_status(self.session, style))
                self.assertIn('path,with comma', shown)
                self.assertIn('--resume' if style == 'unix' else '-Resume', shown)
                (self.session / 'configuration.result').write_text(initial_stage('wrong', ''))
                with self.assertRaises(ContractError):
                    review(self.session, style)
                (self.session / 'configuration.result').unlink()

    def test_dry_run_and_completed_sessions_rejected(self):
        for style in ('unix', 'windows'):
            with self.subTest(style=style):
                platform = self.save(style)
                (self.session / 'request.tsv').write_text(request_document(platform, 'test', '1', ['configuration'], '', '1'))
                with self.assertRaises(ResumeError):
                    resume(self.session, platform, 'test', style)
                self.assertIn('dry-run sessions cannot be resumed', '\n'.join(show_status(self.session, style)))
                self.save(style, statuses=('success', 'success'))
                (self.session / 'request.tsv').write_text(request_document(platform, 'test', '1', ['packages', 'configuration'], '', '0'))
                with self.assertRaises(ResumeError):
                    resume(self.session, platform, 'test', style)

    def test_stage_filter_keeps_current_gates(self):
        stages = [{'Id': 'packages', 'Enabled': True, 'Reason': ''}, {'Id': 'configuration', 'Enabled': False, 'Reason': 'profile'}]
        result = filter_stages(stages, ['configuration'])
        self.assertEqual(result[0]['Reason'], 'resume-selection')
        self.assertFalse(result[1]['Enabled'])
        self.assertEqual(result[1]['Reason'], 'profile')
        self.assertTrue(stages[0]['Enabled'])
        with self.assertRaises(ResumeError):
            filter_stages(stages, ['missing'])

    def test_snapshot_and_legacy_status_do_not_recommend_install_resume(self):
        self.save('unix')
        request_path = self.session / 'request.tsv'
        request_path.write_text(request_document('macos', 'snapshot', '0', ['packages', 'configuration'], '', '0'))
        shown = '\n'.join(show_status(self.session, 'unix'))
        self.assertIn('rerun snapshot restore', shown)
        self.assertNotIn('--resume', shown)
        with self.assertRaisesRegex(ResumeError, 'Snapshot'):
            resume(self.session, 'macos', 'snapshot', 'unix')
        self.save('unix')
        request_path.write_text(request_path.read_text().replace('workflow-request|3', 'workflow-request|2'))
        shown = '\n'.join(show_status(self.session, 'unix'))
        self.assertIn('read-only', shown)
        self.assertNotIn('--resume', shown)

    def test_bad_request_rejected(self):
        self.save('unix')
        request = read_request(self.session)
        request['selected_stages'] = 'packages,packages'
        (self.session / 'request.tsv').write_text(Contract.load('workflow-request').write([request]))
        with self.assertRaises(ContractError):
            read_request(self.session)

    def test_status_request_uses_complete_history(self):
        self.save('unix')
        value, lines = request('workflow-status', {'session': str(self.session), 'style': 'unix'})
        self.assertEqual(value, lines)
        self.assertIn('configuration: failed', '\n'.join(lines))

    def test_completed_sidecar_overrides_failed_summary_and_bad_host_is_rejected(self):
        for style in ('unix', 'windows'):
            platform = self.save(style)
            (self.session / 'request.tsv').write_text(request_document(platform, 'test', '0', ['configuration'], '', '0'))
            with self.assertRaises(ResumeError):
                resume(self.session, 'other-platform', 'test', style)
            (self.session / 'configuration.result').write_text(finish_stage(initial_stage('configuration', ''), 0, False, '', False))
            with self.assertRaises(ResumeError):
                resume(self.session, platform, 'test', style)
            (self.session / 'configuration.result').write_text('corrupt')
            with self.assertRaises(ContractError):
                resume(self.session, platform, 'test', style)
            (self.session / 'configuration.result').unlink()
