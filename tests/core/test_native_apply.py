import os
from pathlib import Path
import shutil
import tempfile
import unittest

from dotfiles_core.errors import ProtocolError
from dotfiles_core.native_apply import NativeFilesystem, native_filesystem
from dotfiles_core.protocol import Result


class NativeApplyTests(unittest.TestCase):
    def test_malformed_observations_fail_closed(self):
        class Broken:
            def invoke(self, operation, context):
                return Result(operation, 0, {'value': []})
        fs = NativeFilesystem(Broken())
        for operation in (lambda: fs.entry('/path'), lambda: fs.state('/path'),
                          lambda: fs.tree('/path'), lambda: fs.equal('/one', '/two', 'copy')):
            with self.assertRaises(ProtocolError):
                operation()

    def test_real_native_observations_preserve_paths_and_identity(self):
        adapters = []
        if os.name != 'nt':
            adapters.append(('unix', shutil.which('bash')))
        powershell = shutil.which(os.environ.get('DOTFILES_TEST_POWERSHELL', 'pwsh'))
        if powershell:
            adapters.append(('windows', powershell))
        for style, shell in adapters:
            with self.subTest(style=style), tempfile.TemporaryDirectory(prefix='apply 中文 ') as directory:
                root = Path(directory)
                source, target = root / 'source $() `literal`.txt', root / 'target.txt'
                source.write_text('payload\n', encoding='utf-8')
                target.hardlink_to(source)
                fs = native_filesystem(style, shell)
                self.assertEqual(fs.entry(str(source)).kind, 'file')
                self.assertNotEqual(fs.state(str(source)), 'absent')
                self.assertEqual(fs.state(str(root / 'absent')), 'absent')
                self.assertTrue(fs.equal(str(source), str(target), 'hardlink'))
                self.assertTrue(fs.equal(str(source), str(target), 'copy'))
                self.assertEqual(set(fs.tree(str(root))), {str(source), str(target)})
                self.assertEqual(fs.anchor(str(root / 'new' / 'nested')), str(root))
                target.unlink()
                target.write_text('changed', encoding='utf-8')
                self.assertFalse(fs.equal(str(source), str(target), 'copy'))
