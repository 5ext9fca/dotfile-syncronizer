#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
session="$test_tmp/old session,one";mkdir "$session"
if [[ "$(uname -s)" == Darwin ]];then platform=macos;profile=macos;entry=macos;extra=()
else
  profile=linux;entry=linux;extra=(--yes)
  if command -v pacman >/dev/null;then platform=linux.pacman
  elif command -v apt-get >/dev/null;then platform=linux.apt
  else platform=linux.dnf;fi
fi
contract_save workflow-request "$platform|$profile|0|packages||0" "$session/request.tsv"
printf '%s\n' "$(contract_fields workflow-summary)" "old|$profile|packages|failed|23|0|$session/run.log|||command-failed|1||packages" > "$session/workflow.tsv"
stage_result_init "$session/packages.result" packages ''
stage_result_artifact "$session/packages.result" recovery_journal "$session/journal,one.tsv"
stage_result_finish "$session/packages.result" 23 0 ''
"$repo_root/workflow/status.sh" "$session" > "$test_tmp/status"
grep -Fq 'exit=23' "$test_tmp/status"
grep -Fq "$session/journal,one.tsv" "$test_tmp/status"
grep -Fq -- '--resume' "$test_tmp/status"
# Exercise the production preflight and session path, not a resume-only bridge.
export XDG_CONFIG_HOME="$test_tmp/config" DOTFILES_BACKUP_DIR="$test_tmp/backups"
"$repo_root/install/$entry.sh" ${extra[@]+"${extra[@]}"} --resume "$session" --dry-run --results "$test_tmp/resumed.tsv" --session-id resume-cli > "$test_tmp/resumed.log"
saved="$(contract_read workflow-request "$(cat "$test_tmp/backups/workflow-resume-cli/request.tsv")")"
[[ "$saved" == "$platform|$profile|0|packages|$session|1" ]]
[[ "$(awk -F '|' '$4=="planned" {print $3}' "$test_tmp/resumed.tsv")" == packages ]]
[[ ! -e "$XDG_CONFIG_HOME" ]]
for option in --only-stage --from-stage;do
  if "$repo_root/install/$entry.sh" ${extra[@]+"${extra[@]}"} --resume "$session" --dry-run "$option" packages > "$test_tmp/rejected.log" 2>&1;then exit 1;fi
done
# Dry-run history must offer another dry run, not an unusable resume command.
contract_save workflow-request "$platform|$profile|0|packages||1" "$session/request.tsv"
for code in 23 75 130;do
  stage_result_finish "$session/packages.result" "$code" 1 ''
  "$repo_root/workflow/status.sh" "$session" > "$test_tmp/status"
  grep -Fq -- 'original command with --dry-run' "$test_tmp/status"
  if grep -Fq -- '--resume' "$test_tmp/status";then exit 1;fi
done
if "$repo_root/install/$entry.sh" ${extra[@]+"${extra[@]}"} --resume "$session" --dry-run > "$test_tmp/rejected.log" 2>&1;then exit 1;fi
# Structured item diagnostics do not depend on logs.
rm "$session/packages.result"
contract_save workflow-request "$platform|$profile|0|packages||0" "$session/request.tsv"
contract_save install-result 'docker|failed|1|exit-23||||' "$session/packages.tsv"
printf '%s\n' "$(contract_fields workflow-summary)" "old|$profile|packages|failed|23|0||$session/packages.tsv||command-failed|1||packages" > "$session/workflow.tsv"
"$repo_root/workflow/status.sh" "$session" > "$test_tmp/status"
grep -Fq 'Item docker: failed (exit-23)' "$test_tmp/status"
if grep -q 'restore' "$test_tmp/status";then exit 1;fi
printf 'corrupt\n' > "$session/packages.result"
if "$repo_root/workflow/status.sh" "$session" > "$test_tmp/rejected.log" 2>&1;then exit 1;fi
printf 'Workflow resume entry and structured failure summary tests passed.\n'
