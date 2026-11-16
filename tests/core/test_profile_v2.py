"""Repository-specific v2/v7 behavior, independent of the migration reference."""
from dataclasses import replace
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from dotfiles_core.apply_planning import Paths, Planner
from dotfiles_core.apply_rules import ApplyItem, ApplyConfigError
from dotfiles_core.contracts import Contract, ContractError
from dotfiles_core.install_config import ROOT, read_items
from dotfiles_core.install_planning import components, prepare as install_prepare, select
from dotfiles_core.workflow_preflight import Inputs, prepare
from dotfiles_core.workflow_review import read_request, resume, ResumeError
from dotfiles_core.workflow_rules import read_profile
from test_workflow_preflight import Observations
from test_apply_planning import Observations as Filesystem


class ProfileV2Tests(unittest.TestCase):
    def test_defaults_do_not_observe_installation_or_wsl(self):
        for platform, style in [('macos', 'unix'), ('linux', 'unix'), ('windows', 'windows'), ('wsl', 'unix')]:
            native = Observations()
            inputs = Inputs(str(ROOT), 'windows' if style == 'windows' else 'macos', style,
                            platform, 'default', '/config', '/backup', False, False, True)
            result = prepare(inputs, native, Paths())
            self.assertEqual(native.calls, ['configuration'])
            self.assertEqual(result.installation, [])
            self.assertFalse(result.inputs.mirrors)
            self.assertEqual([stage.Id for stage in result.stages if stage.Enabled], ['configuration'])

    def test_none_never_falls_back_to_all(self):
        def forbidden(*args):
            self.fail('none must not observe anything')
        self.assertEqual(select([{'id': 'tool'}], 'none', 'normal', forbidden), [])
        self.assertEqual(components('none', []), [])
        self.assertEqual(components('standalone', [], ['standalone']), ['standalone'])
        fs = Filesystem()
        rows = Planner(fs, '/backup').components([ApplyItem('tool', 'source', 'home', '.tool', 'copy')],
                                                 '/repo', '', ['none'], roots={'home': ''})
        self.assertEqual(rows, [])
        self.assertEqual(fs.calls, [])
        self.assertEqual(Planner(fs, '/backup').components(
            [ApplyItem('tool', 'source', 'home', '.tool', 'copy')], '/repo', '', [], roots={'home': ''}), [])
        self.assertEqual(fs.calls, [])

    def test_custom_empty_profile_and_explicit_mirror_override(self):
        profile = dict(schema_version='2', install='none', components='none', shell='none', mirrors='none',
                       wsl='none', wsl_profile='none')
        inputs = Inputs(str(ROOT), 'macos', 'unix', 'custom', 'empty', '', '/backup', True, True, True)
        with patch('dotfiles_core.workflow_preflight.read_profile', return_value=profile):
            native = Observations()
            result = prepare(inputs, native, Paths())
            self.assertEqual(native.calls, [])
            self.assertFalse(any(stage.Enabled for stage in result.stages))
            native = Observations()
            result = prepare(replace(inputs, mirrors_explicit=True, only='mirrors'), native, Paths())
            self.assertEqual(native.calls, ['mirrors'])
            self.assertTrue(result.inputs.mirrors)

    def test_home_does_not_protect_entire_user_directory(self):
        native = Observations()
        inputs = Inputs(str(ROOT), 'macos', 'unix', 'macos', 'home', 'invalid-relative', '/home/.backups',
                        True, True, False, roots={'home': '/home', 'config_home': 'invalid-relative'})
        with patch('dotfiles_core.workflow_preflight.read_items', return_value=[ApplyItem('git', 'source', 'home', '.gitconfig', 'copy')]), \
             patch('dotfiles_core.workflow_preflight.read_profile', return_value=dict(install='none', components='git', shell='none', mirrors='none', wsl='none')):
            result = prepare(inputs, native, Paths())
            self.assertEqual(result.session, '/home/.backups/workflow-home')
            native.plan = [dict(source='/repo/source', target='/home/.gitconfig', reason='new', privilege='none')]
            with self.assertRaisesRegex(Exception, 'planned file'):
                prepare(replace(inputs, backup='/home/.gitconfig'), native, Paths())

    def test_pre_migration_v2_session_restores_custom_profile(self):
        # Literal wire data from the pre-migration contract, not the new writer.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            request = ('# dotfiles|workflow-request|2\n'
                       'platform|profile|china_mirrors|selected_stages|resume_parent|dry_run\n'
                       'macos|custom-profile|0|configuration||0\n')
            (root / 'request.tsv').write_text(request)
            (root / 'workflow.tsv').write_text('|'.join(Contract.load('workflow-summary').fields) + '\n')
            saved = resume(root, 'macos', 'macos', 'unix')
            self.assertEqual(saved['profile'], 'custom-profile')
            self.assertEqual(saved['resume_stages'], ['configuration'])
            with self.assertRaises(ResumeError):
                resume(root, 'macos', 'macos', 'unix', profile_explicit=True)
            (root / 'request.tsv').write_text(request.replace('workflow-request|2', 'workflow-request|1'))
            with self.assertRaises(ContractError):
                read_request(root)

    def test_install_plan_v7_preserves_font_family(self):
        items = read_items(ROOT / 'tests/fixtures/install/font-download', 'linux.apt')
        planned = install_prepare(items, False, False)
        self.assertEqual(Contract.load('install-plan').version, '7')
        fonts = [item for item in planned if item['method'] == 'font-download']
        self.assertTrue(fonts)
        for item in fonts:
            self.assertTrue(item['font_family'])
            self.assertEqual(item['schema_version'], '7')
            self.assertIn(item['font_family'], Contract.load('install-plan').row(item))
