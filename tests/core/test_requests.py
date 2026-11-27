import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from dotfiles_core.errors import CoreError, ProtocolError, AdapterError
from dotfiles_core.install_config import ROOT
from dotfiles_core.protocol import Request, Result, write_json
from dotfiles_core.requests import run, read_result, prepare


class RequestTests(unittest.TestCase):
    def test_windows_result_status_preserves_signed_native_code(self):
        with tempfile.TemporaryDirectory() as directory:
            result = Path(directory) / 'result.json'
            write_json(result, Result('install-execute-native', -1978335212, {'error': 'native failure'}).document())
            with patch('dotfiles_core.requests.os.name', 'nt'):
                with self.assertRaises(AdapterError) as raised:
                    read_result(result, 'install-execute-native', 0x8a150014)
                self.assertEqual(raised.exception.exit_code, -1978335212)
                with self.assertRaises(ProtocolError):
                    read_result(result, 'install-execute-native', 0)

    def test_result_consistency(self):
        with tempfile.TemporaryDirectory() as directory:
            request, result = Path(directory) / 'request.json', Path(directory) / 'result.json'
            write_json(request, Request('contract-read', {'kind': 'git-result', 'text': 'broken'}).document())
            self.assertEqual(run(request, result), 1)
            with self.assertRaises(CoreError):
                read_result(result, 'contract-read', 1)
            with self.assertRaises(ProtocolError):
                read_result(result, 'contract-read', 0)
            write_json(result, Result('contract-read', 0, {'value': [], 'lines': [7]}).document())
            with self.assertRaises(ProtocolError):
                read_result(result, 'contract-read', 0)
            result.unlink()
            with self.assertRaises(ProtocolError):
                read_result(result, 'contract-read', 0)

    def test_native_framing_and_encoding(self):
        value = '中文 "quote" \\ $HOME `literal`' + ''.join(chr(i) for i in range(1, 32))
        with tempfile.TemporaryDirectory() as directory:
            arguments, request = Path(directory) / 'arguments', Path(directory) / 'request.json'
            arguments.write_bytes(('test\0text\0' + value + '\0').encode('utf-8'))
            prepare(arguments, request)
            self.assertEqual(Request.read(request).context, {'text': value})
            for content in (b'test', b'test\0key\0', b'test\0key\0a\0key\0b\0'):
                arguments.write_bytes(content)
                with self.assertRaises(ProtocolError):
                    prepare(arguments, request)

    def test_resume_error_retains_public_exit_code(self):
        with tempfile.TemporaryDirectory() as directory:
            request, result = Path(directory) / 'request.json', Path(directory) / 'result.json'
            from dotfiles_core.workflow_review import ResumeError
            write_json(request, Request('workflow-preflight-native', {}).document())
            with patch('dotfiles_core.native_preflight.request', side_effect=ResumeError('Invalid resume selection')):
                self.assertEqual(run(request, result), 2)
            with self.assertRaises(CoreError) as raised:
                read_result(result, 'workflow-preflight-native', 2)
            self.assertEqual(raised.exception.exit_code, 2)

    def test_large_native_request_and_cleanup(self):
        powershell = shutil.which(os.environ.get('DOTFILES_TEST_POWERSHELL', 'pwsh'))
        with tempfile.TemporaryDirectory(prefix='dotfiles 请求 ') as directory:
            root = Path(directory)
            scratch = root / 'scratch'
            scratch.mkdir()
            source = root / 'source.txt'
            payload = '\n'.join('中文 "literal" \\ ' + str(i) + 'x' * 120 + '|success' for i in range(700))
            source.write_text(payload, encoding='utf-8')
            env = dict(os.environ, TMPDIR=str(scratch))
            if os.name != 'nt':
                script = 'source "$1/lib/data-contract.sh"; contract_write git-result "$(cat "$2")"'
                process = subprocess.run(['bash', '-c', script, 'test', str(ROOT), str(source)], env=env, capture_output=True, text=True)
                self.assertEqual(process.returncode, 0, process.stderr)
                self.assertEqual(process.stdout, '# dotfiles|git-result|1\nkey|status\n' + payload + '\n')
                self.assertEqual(list(scratch.iterdir()), [])
            if powershell:
                script_path = root / 'request test.ps1'
                script_path.write_text('''param($Repo, $Source)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $Repo 'lib/data-contract.ps1')
Invoke-DotfilesRequest contract-write @{kind='git-result';text=[IO.File]::ReadAllText($Source, [Text.Encoding]::UTF8)}
''', encoding='utf-8-sig')
                process = subprocess.run([powershell, '-NoProfile', '-File', str(script_path), str(ROOT), str(source)], env=env, capture_output=True, encoding='utf-8')
                self.assertEqual(process.returncode, 0, process.stderr)
                self.assertEqual(process.stdout, '# dotfiles|git-result|1\nkey|status\n' + payload + '\n')
                self.assertEqual(list(scratch.iterdir()), [])
            elif os.name == 'nt':
                self.skipTest('PowerShell unavailable')
