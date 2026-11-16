#!/usr/bin/env bash
# Each lease runs in a subshell; parent environment intentionally stays unchanged.
# shellcheck disable=SC2031
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/deployment-lock.sh
source "$repo_root/lib/deployment-lock.sh"
work="$(mktemp -d)";trap 'rm -rf "$work"' EXIT
export DOTFILES_DEPLOYMENT_LOCK="$work/lock"
unset DOTFILES_DEPLOYMENT_TOKEN
# Keep one real child alive until the parent has observed contention.
mkfifo "$work/release"
cat > "$work/worker.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
source "$1/lib/deployment-lock.sh"
worker() { printf 'ready\n' > "$2/ready";read -r release < "$2/release"; }
deployment_run 0 worker "$@"
SCRIPT
"$BASH" "$work/worker.sh" "$repo_root" "$work" &
worker=$!
for ((i=0;i<100;i++));do [[ ! -f "$work/ready" ]] || break;sleep 0.05;done
[[ -f "$work/ready" ]];kill -0 "$worker"
if deployment_run 0 touch "$work/wrong" 2>/dev/null;then exit 1;fi
[[ ! -e "$work/wrong" ]]
# Read-only operations never contend with the deployment lease.
deployment_run 1 touch "$work/dry"
printf 'release\n' > "$work/release"
wait "$worker"
[[ ! -e "$DOTFILES_DEPLOYMENT_LOCK" ]]
nested() { deployment_run 0 touch "$work/nested"; }
deployment_run 0 nested
[[ -f "$work/nested" && ! -e "$DOTFILES_DEPLOYMENT_LOCK" ]]
if deployment_run 0 false;then exit 1;fi
[[ ! -e "$DOTFILES_DEPLOYMENT_LOCK" ]]
# Failure to collect ownership metadata precedes lock creation.
"$dotfiles_python_executable" - <<'PYTEST'
import os
from pathlib import Path
from unittest.mock import patch
from dotfile_viewer.lease import acquire
with patch('dotfile_viewer.lease.socket.gethostname', side_effect=OSError('metadata')):
    try:
        acquire()
    except OSError:
        pass
    else:
        raise AssertionError('Expected metadata failure')
assert not Path(os.environ['DOTFILES_DEPLOYMENT_LOCK']).exists()
PYTEST
# Unknown/stale ownership is never silently reclaimed.
mkdir "$DOTFILES_DEPLOYMENT_LOCK"
printf '999999|unknown|token\n' > "$DOTFILES_DEPLOYMENT_LOCK/owner"
if deployment_run 0 touch "$work/wrong" 2>/dev/null;then exit 1;fi
[[ -f "$DOTFILES_DEPLOYMENT_LOCK/owner" && ! -e "$work/wrong" ]]
# Public mutating entry points acquire the lease before planning or recovery.
for entry in apply/mirrors.sh;do
  set +e
  "$BASH" "$repo_root/$entry" > "$work/entry.log" 2>&1
  code=$?
  set -e
  [[ "$code" == 73 && -f "$DOTFILES_DEPLOYMENT_LOCK/owner" ]]
done
set +e
"$BASH" "$repo_root/apply/apply.sh" --restore "$work/missing-journal" > "$work/entry.log" 2>&1
code=$?
set -e
[[ "$code" == 2 && -f "$DOTFILES_DEPLOYMENT_LOCK/owner" ]]
printf 'Deployment contention, nesting, read-only bypass and failure cleanup passed.\n'
