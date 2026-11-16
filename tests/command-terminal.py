#!/usr/bin/env python3
"""Exercise the command runner with a real controlling terminal, offline."""
import errno
import os
from pathlib import Path
import pty
import select
import signal
import time

ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get('DOTFILES_TEST_BASH', 'bash')


def exercise(command, reply, expected, workflow=False):
    pid, terminal = pty.fork()
    if pid == 0:
        if workflow:
            os.execvp(BASH, [BASH, str(ROOT / 'tests/fixtures/command/workflow-terminal.sh'), str(ROOT)])
        os.execvp(BASH, [BASH, '-c',
            'source "$1/lib/command.sh"; command_run mutation 0 0 "" -- bash -c "$2"; '
            'code=$?; printf "OUTCOME=%s\\n" "$code"', '_', str(ROOT), command])
    transcript = b''
    sent = 0
    done = False
    try:
        # A workflow crosses Python/native request boundaries and publishes
        # several snapshots; keep the bounded harness independent of CPU load.
        deadline = time.monotonic() + (60 if workflow else 15)
        while time.monotonic() < deadline:
            if select.select([terminal], [], [], 0.1)[0]:
                try:
                    chunk = os.read(terminal, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not chunk:
                    break
                transcript += chunk
                prompts = transcript.count(b'READY')
                if prompts > sent:
                    os.write(terminal, reply)
                    sent += 1
            if os.waitpid(pid, os.WNOHANG)[0]:
                done = True
                break
        assert sent and expected in transcript, transcript.decode(errors='replace')
        if workflow:
            assert sent == 3 and transcript.count(b'INPUT_OK') == 3, transcript.decode(errors='replace')
            assert b'NEXT_STAGE_OK' in transcript, transcript.decode(errors='replace')
    finally:
        if not done:
            # The test owns this isolated terminal session.
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        os.close(terminal)


exercise('echo READY; read -r value; printf "VALUE=%s\\n" "$value"',
         b'literal input\n', b'VALUE=literal input')
exercise('echo READY; sleep 60', b'\x03', b'OUTCOME=130')
print('Controlling-terminal input and Ctrl-C propagation passed.')

exercise('', b'test input\nstdin input\n', b'OUTCOME=0', workflow=True)
print('Workflow preparation, installation items and subsequent stage preserve terminal input.')
