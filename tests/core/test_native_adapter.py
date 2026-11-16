import os
from pathlib import Path
import shutil
import tempfile
import unittest
import time
import sys
from unittest.mock import patch

from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.install_config import ROOT
from dotfiles_core.install_planning import prepare
from dotfiles_core.protocol import Adapter, Request, Result, write_json
from dotfiles_core.native_protocol import arguments, OPERATIONS
from dotfiles_core.native_observation import NativeObservation
from dotfiles_core.native_installation import NativeInstallation
from dotfiles_core.native_installation import request as native_request
from dotfiles_core.contracts import Contract


class NativeAdapterTests(unittest.TestCase):
    def test_foreign_platform_inspection_rejects_only_pending_items(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / 'tool.conf').write_text(
                '[linux.apt]\norder=10\nmethod=apt\npackages=tool\nsource_kind=default\nenvironments=native\n')
            context = dict(style='windows', native_shell=sys.executable, native_context={},
                           directory=directory, platform='linux.apt', mirrors='0', wsl='1', inspect='1')
            with patch.object(Adapter, 'invoke', side_effect=AssertionError('Excluded tool was queried')):
                items, _ = native_request('install-plan-native', context)
                self.assertEqual(items[0]['reason'], 'environment-not-selected:wsl')
                context['wsl'] = '0'
                with self.assertRaises(ProtocolError):
                    native_request('install-plan-native', context)

    def test_malformed_success_is_not_accepted(self):
        item = prepare([dict(id='tool', method='apt')], False, False)[0]
        class BrokenAdapter:
            data = {'unexpected': True}
            def invoke(self, operation, context):
                return Result(operation, 0, self.data)
        adapter = BrokenAdapter()
        runner = NativeInstallation(adapter, '')
        with self.assertRaises(ProtocolError):
            runner.install(item)
        with self.assertRaises(ProtocolError):
            runner.publish('unused', 'text')
        for data in ({'unexpected': True}, {'state': []}, {'state': '', 'extra': True}):
            adapter.data = data
            with self.subTest(data=data), self.assertRaises(ProtocolError):
                runner.observe(item)

    @unittest.skipIf(os.name == 'nt', 'POSIX executable fixture; native Windows command fixtures run separately')
    def test_native_failure_blocks_later_items(self):
        for platform, command in self.adapters():
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                binary = root / ('sudo' if platform == 'unix' else 'winget.exe')
                calls = root / 'calls'
                binary.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$DOTFILES_TEST_NATIVE_CALLS"\nexit 23\n')
                binary.chmod(0o755)
                context = 'linux.apt|0|brew||' + directory if platform == 'unix' else {'DryRun': False}
                items = prepare([dict(id=name, method='apt' if platform == 'unix' else 'winget', packages=name, source_repo='winget')
                                 for name in ('first', 'later')], False, False)
                report = root / 'report.tsv'
                adapter = Adapter({name: command for name in ('install-command', 'publish-report')})
                with patch.dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH'], DOTFILES_TEST_NATIVE_CALLS=str(calls)):
                    result = NativeInstallation(adapter, context).execute(items, dry=False, resume=False, results=str(report), style=platform)
                self.assertEqual(result.exit_code, 23)
                rows = Contract.load('install-result').read(report.read_text())
                self.assertEqual([row['status'] for row in rows], ['failed', 'blocked'])
                self.assertEqual(rows[0]['reason'], 'exit-23')
                self.assertEqual(len(calls.read_text().splitlines()), 1)
                policy = root / 'execution.tsv'
                source = (ROOT / 'install/schema/execution.tsv').read_text()
                lines = []
                for line in source.splitlines():
                    fields = line.split('\t')
                    if fields[:2] == ['*', 'install']:
                        fields[3] = '0,23'
                        line = '\t'.join(fields)
                    lines.append(line)
                policy.write_text('\n'.join(lines) + '\n')
                calls.write_text('')
                with patch.dict(os.environ, PATH=directory + os.pathsep + os.environ['PATH'], DOTFILES_TEST_NATIVE_CALLS=str(calls)):
                    result = NativeInstallation(adapter, context, str(policy)).execute(items, dry=False, resume=False, results=str(report), style=platform)
                self.assertEqual(result.exit_code, 0)
                self.assertEqual(len(calls.read_text().splitlines()), 2)

    @unittest.skipIf(os.name == 'nt', 'Unix controlling-terminal contract')
    def test_native_command_terminal_input_and_interrupt(self):
        import errno
        import pty
        import select
        import signal
        with tempfile.TemporaryDirectory(prefix='dotfiles terminal ') as directory:
            root = Path(directory)
            command_path = root / 'sudo'
            for interrupt in (False, True):
                command_path.write_text('#!/bin/bash\necho READY\n' + (
                    'sleep 3\n' if interrupt else 'read -r first </dev/tty\nread -r second\nprintf "INPUT=%s,%s\\n" "$first" "$second"\n'))
                command_path.chmod(0o755)
                pid, terminal = pty.fork()
                if pid == 0:
                    os.environ['PATH'] = str(root) + os.pathsep + os.environ['PATH']
                    os.environ['DOTFILES_PYTHON'] = sys.executable
                    item = prepare([dict(id='tool', method='apt', packages='test.fixture')], False, False)[0]
                    adapter = Adapter({'install-command': ['bash', str(ROOT / 'lib/core-adapter.sh')]})
                    code = 0
                    try:
                        adapter.invoke('install-command', {'item': item, 'native_context': 'linux.apt|0|brew||' + str(root), 'mode': 'normal'})
                    except AdapterError as exc:
                        code = exc.exit_code
                    except BaseException as exc:
                        print('UNEXPECTED=' + repr(exc), flush=True)
                        code = 99
                    print('OUTCOME=' + str(code), flush=True)
                    os._exit(0)
                transcript = b''
                sent = done = False
                try:
                    deadline = time.monotonic() + 20
                    while time.monotonic() < deadline:
                        if select.select([terminal], [], [], 0.1)[0]:
                            try:
                                chunk = os.read(terminal, 65536)
                            except OSError as exc:
                                if exc.errno != errno.EIO:
                                    raise
                                break
                            if not chunk:
                                break
                            transcript += chunk
                            if not sent and b'READY' in transcript:
                                os.write(terminal, b'\x03' if interrupt else b'terminal value\nstdin value\n')
                                sent = True
                        if os.waitpid(pid, os.WNOHANG)[0]:
                            done = True
                            break
                    text = transcript.decode(errors='replace')
                    self.assertTrue(sent, text)
                    self.assertIn('OUTCOME=' + ('130' if interrupt else '0'), text)
                    if not interrupt:
                        self.assertIn('INPUT=terminal value,stdin value', text)
                finally:
                    if not done:
                        try:
                            os.kill(pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        os.waitpid(pid, 0)
                    os.close(terminal)

    def adapters(self):
        if os.name != 'nt':
            yield 'unix', ['bash', str(ROOT / 'lib/core-adapter.sh')]
        powershell = shutil.which(os.environ.get('DOTFILES_TEST_POWERSHELL', 'pwsh'))
        if powershell:
            yield 'windows', [powershell, '-NoProfile', '-File', str(ROOT / 'lib/core-adapter.ps1')]

    def test_publication_and_real_discovery(self):
        for platform, command in self.adapters():
            with self.subTest(platform=platform), tempfile.TemporaryDirectory(prefix='dotfiles native 中文 ') as directory:
                root = Path(directory)
                scratch = root / 'scratch'
                scratch.mkdir()
                adapter = Adapter({operation: command for operation in OPERATIONS}, scratch=scratch)
                target = root / 'report.txt'
                document = '中文 "literal" $() `value`\nsecond line\n'
                adapter.invoke('publish-report', {'path': str(target), 'text': document, 'mode': 'create'})
                self.assertEqual(target.read_text(), document)
                with self.assertRaises(AdapterError):
                    adapter.invoke('publish-report', {'path': str(target), 'text': 'replacement', 'mode': 'create'})
                self.assertEqual(target.read_text(), document)
                adapter.invoke('publish-report', {'path': str(target), 'text': 'new', 'mode': 'replace'})
                self.assertEqual(target.read_text(), 'new')
                executable = root / 'tool.exe'
                executable.write_text('fixture')
                discovery = ('manual:file:root:' + str(executable).lstrip('/')) if platform == 'unix' else 'manual:file:program_files:tool.exe'
                item = prepare([dict(id='tool', method='apt' if platform == 'unix' else 'winget', discovery=discovery)], False, False)[0]
                context = 'linux.apt|1|brew||' + str(root) if platform == 'unix' else {'ProgramFiles': str(root), 'DryRun': True}
                observer = NativeObservation(adapter, context, platform)
                observed = NativeInstallation(adapter, context).observe(item, 'normal')
                self.assertEqual(observed['action'], 'skip')
                self.assertEqual(observed['detected_method'], 'manual')
                self.assertIn('tool.exe', observed['detected_paths'])
                executable.unlink()
                observed = observer.observe(observed, 'resume')
                self.assertEqual(observed['action'], 'install')
                self.assertEqual(observed['detected_paths'], '')
                if os.name != 'nt':
                    probe = root / 'probe-tool'
                    probe.write_text('#!/bin/bash\nexit 0\n')
                    probe.chmod(0o755)
                    probe_item = prepare([dict(id='probe', method='script' if platform == 'unix' else 'winget', probe_command=str(probe))], False, False)[0]
                    self.assertEqual(observer.observe(probe_item, 'resume')['action'], 'skip')
                # Exercise the real native handler only in its non-mutating mode.
                item = prepare([dict(id='tool', method='apt' if platform == 'unix' else 'winget', packages='test.fixture', source_repo='winget')], False, False)[0]
                runner = NativeInstallation(adapter, context)
                report = root / 'install.tsv'
                outcome = runner.execute([item], dry=True, resume=False, results=str(report), style=platform)
                self.assertEqual(outcome.exit_code, 0)
                self.assertEqual(Contract.load('install-result').read(report.read_text())[0]['status'], 'planned')
                value, lines = native_request('install-execute-native', {
                    'style': platform, 'native_shell': str(Path(shutil.which(command[0])).resolve()),
                    'native_context': context, 'items': [item], 'dry': '1', 'resume': '0', 'results': str(report)})
                self.assertEqual(value['exit_code'], 0)
                self.assertEqual(lines, [])
                self.assertEqual(list(scratch.iterdir()), [])

    def test_allowlist_rejected_before_projection(self):
        with tempfile.TemporaryDirectory() as directory:
            request = Path(directory) / 'request.json'
            output = Path(directory) / 'arguments'
            write_json(request, Request('shell-eval', {'text': 'touch unwanted'}).document())
            with self.assertRaises(ProtocolError):
                arguments(request, output, 'unix')
            self.assertFalse(output.exists())
