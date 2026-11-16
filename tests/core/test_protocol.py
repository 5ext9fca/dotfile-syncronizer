import os
from pathlib import Path
import sys
import tempfile
import unittest

from dotfiles_core.errors import AdapterError, ProtocolError
from dotfiles_core.protocol import Adapter, Request, Result, dispatch, read_json, write_json, exit_codes_match


class ProtocolTests(unittest.TestCase):
    def test_windows_signed_native_status(self):
        self.assertTrue(exit_codes_match(0x8a150014, -1978335212, windows=True))
        self.assertFalse(exit_codes_match(0x8a150014, -1978335212))
        self.assertFalse(exit_codes_match(23, 42, windows=True))
        self.assertFalse(exit_codes_match(0, 0x100000000, windows=True))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles 协议 ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def adapter(self, body):
        script = self.root / "adapter fixture.py"
        script.write_text("import json, os, sys\nfrom pathlib import Path\n"
                          "request = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))\n"
                          + body, encoding="utf-8")
        return Adapter({"observe": [sys.executable, "-B", str(script)]}, scratch=self.root)

    def test_unicode_and_literal_arguments(self):
        adapter = self.adapter("Path(sys.argv[2]).write_text(json.dumps({"
                               "'protocol_version': 1, 'operation': request['operation'], "
                               "'exit_code': 0, 'data': request['context']}, ensure_ascii=False), encoding='utf-8')\n")
        context = {"path": "中文 空格/$HOME/`command`/\"quotes\"", "token": "nested-owner"}
        self.assertEqual(adapter.invoke("observe", context).data, context)
        self.assertEqual(list(self.root.glob("dotfiles-adapter-*")), [])

    def test_private_directory(self):
        if os.name == "nt":
            self.skipTest("POSIX permissions")
        adapter = self.adapter("assert Path(sys.argv[1]).parent.stat().st_mode & 0o077 == 0\n"
                               "Path(sys.argv[2]).write_text(json.dumps({'protocol_version': 1, "
                               "'operation': 'observe', 'exit_code': 0, 'data': {}}))\n")
        adapter.invoke("observe", {})

    def test_missing_malformed_and_mismatched_results(self):
        for body in ("pass\n", "Path(sys.argv[2]).write_text('{')\n",
                     "Path(sys.argv[2]).write_text(json.dumps({'protocol_version': 1, "
                     "'operation': 'other', 'exit_code': 0, 'data': {}}))\n",
                     "Path(sys.argv[2]).write_text(json.dumps({'protocol_version': 1, "
                     "'operation': 'observe', 'exit_code': 0, 'data': {}}))\nsys.exit(7)\n"):
            with self.subTest(body=body), self.assertRaises(ProtocolError):
                self.adapter(body).invoke("observe", {})
            self.assertEqual(list(self.root.glob("dotfiles-adapter-*")), [])

    def test_failed_operation(self):
        adapter = self.adapter("Path(sys.argv[2]).write_text(json.dumps({'protocol_version': 1, "
                               "'operation': 'observe', 'exit_code': 7, 'data': {}}))\nsys.exit(7)\n")
        with self.assertRaises(AdapterError) as error:
            adapter.invoke("observe", {})
        self.assertEqual(error.exception.exit_code, 7)

    def test_allowlist(self):
        with self.assertRaises(ProtocolError):
            Adapter({}).invoke("arbitrary-command", {})
        request = self.root / "request.json"
        write_json(request, Request("unknown", {}).document())
        with self.assertRaises(ProtocolError):
            dispatch(request, self.root / "result.json", {})

    def test_strict_json(self):
        path = self.root / "bad.json"
        for document in ('[]', '{"x":1,"x":2}', '{"x":NaN}', '\xff'):
            path.write_text(document, encoding="utf-8")
            with self.subTest(document=document), self.assertRaises(ProtocolError):
                read_json(path)

    def test_dispatch(self):
        request, result = self.root / "request.json", self.root / "result.json"
        write_json(request, Request("observe", {"name": "字体"}).document())
        code = dispatch(request, result, {"observe": lambda ctx: Result("observe", 0, ctx)})
        self.assertEqual(code, 0)
        self.assertEqual(Result.read(result, "observe").data, {"name": "字体"})

    @unittest.skipIf(os.name == "nt", "POSIX controlling terminal")
    def test_terminal_input_is_inherited(self):
        import errno
        import pty
        import select
        import signal
        import time

        adapter = self.adapter("assert sys.stdin.isatty()\nprint('READY', flush=True)\n"
                               "value = input()\n"
                               "Path(sys.argv[2]).write_text(json.dumps({'protocol_version': 1, "
                               "'operation': 'observe', 'exit_code': 0, 'data': {'input': value}}))\n")
        pid, terminal = pty.fork()
        if pid == 0:
            try:
                result = adapter.invoke("observe", {})
                print('RESULT=' + result.data['input'], flush=True)
                os._exit(0)
            except BaseException:
                os._exit(1)
        transcript = b""
        sent = False
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if not select.select([terminal], [], [], 0.1)[0]:
                    continue
                try:
                    chunk = os.read(terminal, 65536)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                transcript += chunk
                if b"READY" in transcript and not sent:
                    os.write(terminal, b"literal $HOME input\n")
                    sent = True
                if b"RESULT=literal $HOME input" in transcript:
                    break
            self.assertIn(b"RESULT=literal $HOME input", transcript)
        finally:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
            os.close(terminal)
