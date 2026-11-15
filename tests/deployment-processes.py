"""Exercise real process contention and unclean exit without host mutations."""
import os
from pathlib import Path
import signal
import sys
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
WINDOWS = os.name == "nt"
POWERSHELL = WINDOWS or "--powershell" in sys.argv


def stop(process):
    if process.poll() is None:
        if WINDOWS:
            process.kill()
        else:
            os.killpg(process.pid, signal.SIGKILL)
    process.wait(timeout=10)


def wait_for(process, predicate):
    deadline = time.monotonic() + 15
    while not predicate():
        if process.poll() is not None:
            raise AssertionError("Worker exited before readiness")
        if time.monotonic() > deadline:
            raise AssertionError("Worker readiness timed out")
        time.sleep(0.02)


with tempfile.TemporaryDirectory(prefix="dotfiles-process-contract-") as directory:
    root = Path(directory)
    env = dict(os.environ, DOTFILES_DEPLOYMENT_LOCK=str(root / "lock"))
    env.pop("DOTFILES_DEPLOYMENT_TOKEN", None)
    if POWERSHELL:
        runtime = os.environ.get("DOTFILES_TEST_POWERSHELL", "powershell.exe" if WINDOWS else "pwsh")
        worker = root / "worker.ps1"
        worker.write_text('''param($Repo, $Root, $Mode)
$ErrorActionPreference = 'Stop'
. (Join-Path $Repo 'lib/deployment-lock.ps1')
Invoke-DeploymentLocked $false {
    if ($Mode -eq 'contender') { [IO.File]::WriteAllText((Join-Path $Root 'wrong'), 'wrong'); return }
    [IO.File]::WriteAllText((Join-Path $Root 'ready'), 'ready')
    while ($true) { Start-Sleep -Seconds 1 }
}
''')
        command = [runtime, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(worker), str(REPO), str(root)]
    else:
        runtime = os.environ.get("DOTFILES_TEST_BASH", "bash")
        worker = root / "worker.sh"
        worker.write_text('''set -euo pipefail
source "$1/lib/deployment-lock.sh"
work() {
  if [[ "$3" == contender ]];then touch "$2/wrong";return;fi
  touch "$2/ready"
  while :;do sleep 1;done
}
deployment_run 0 work "$@"
''')
        command = [runtime, str(worker), str(REPO), str(root)]
    process = subprocess.Popen(command + ["owner"], env=env, start_new_session=not WINDOWS,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for(process, lambda: (root / "ready").exists())
        for phase in ("live", "terminated"):
            if phase == "terminated":
                stop(process)
            result = subprocess.run(command + ["contender"], env=env, timeout=15,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            assert result.returncode != 0, phase
            assert not (root / "wrong").exists(), phase
            assert (root / "lock" / "owner").exists(), phase
    finally:
        stop(process)
    if not POWERSHELL:
        report = root / "report"
        report.write_text("complete previous snapshot\n")
        process = subprocess.Popen([runtime, "-c", 'source "$1/lib/atomic-report.sh"; atomic_report_write "$2"',
                                    "atomic-worker", str(REPO), str(report)], stdin=subprocess.PIPE,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            process.stdin.write(b"partial next snapshot\n")
            process.stdin.flush()
            wait_for(process, lambda: any(p.stat().st_size for p in root.glob("report.tmp.*")))
            stop(process)
            assert report.read_text() == "complete previous snapshot\n"
        finally:
            process.stdin.close()
            stop(process)
print("Real process contention, retained unclean-exit lease and report integrity passed.")
