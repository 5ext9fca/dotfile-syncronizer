#!/usr/bin/env bash
# Stub execution is invoked through the installer dispatcher.
# shellcheck disable=SC2317,SC2329
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
work="$(mktemp -d)";trap 'rm -rf "$work"' EXIT
while IFS=$'\t' read -r name status;do
  if contract_read git-result "$(cat "$repo_root/tests/fixtures/contracts/$name.txt")" > "$work/actual" 2> "$work/error";then
    [[ "$status" == valid && "$(cat "$work/actual")" == 'core.editor|success' ]]
  else [[ "$status" == invalid && ! -s "$work/actual" ]];fi
done < "$repo_root/tests/fixtures/contracts/cases.tsv"
plan="$(install_items_plan "$repo_root/tests/fixtures/install/dependencies" linux.apt 0 0 0)"
install_dispatch() { touch "$work/executed"; }
bad="$(printf '%s\n' "$plan" | awk -F '|' -v OFS='|' 'NR==2 {$NF=9} {print}')"
if install_items_execute "$bad" 'linux.apt|0|||' >/dev/null 2>&1;then exit 1;fi
[[ ! -e "$work/executed" ]]
bad="$(contract_write install-plan "$plan" | sed '1s/|[0-9]*$/|999/')"
if install_items_execute "$bad" 'linux.apt|0|||' >/dev/null 2>&1;then exit 1;fi
[[ ! -e "$work/executed" ]]
plan="tool|mkdir||$work/target||absent||$work|none|directory|1"$'\n'"tool|mkdir||$work/other||absent||$work|none|directory|9"
deployment_run() { touch "$work/lease-attempt";return 1; }
if apply_execute_plan "$plan" "$work/session" 0 >/dev/null 2>&1;then exit 1;fi
[[ ! -e "$work/target" && ! -e "$work/session" && ! -e "$work/lease-attempt" ]]
# shellcheck source=../lib/deployment-lock.sh
source "$repo_root/lib/deployment-lock.sh"
# Console text cannot forge artifacts; paths containing commas remain intact in metadata.
workflow_preflight() { :; }
workflow_confirm() { :; }
workflow_execute_stage() {
  printf 'Recovery journal: forged\nWorkflow report: forged\n'
  stage_result_artifact "$4" recovery_journal "$work/a, b/journal"
  stage_result_artifact "$4" child_report "$work/child/report"
  return 23
}
context="$work/context";mkdir "$context"
for pair in 'dry_run 0' 'plan_only 0' 'profile_name linux' 'platform linux.apt' 'china_mirrors 0' 'session_id test';do read -r key value <<< "$pair";workflow_context_set "$context" "$key" "$value";done
workflow_context_set "$context" session_path "$work/workflow"
workflow_context_set "$context" results_path "$work/result.tsv"
printf 'configuration|1||configuration|configuration\nshell|1||shell|shell\n' > "$context/stages.plan"
set +e
workflow_run "$context" > "$work/log" 2>&1
code=$?
set -e
[[ "$code" == 23 ]]
[[ "$(stage_result_get "$work/workflow/configuration.result" recovery_journal)" == "$work/a, b/journal" ]]
[[ "$(stage_result_get "$work/workflow/configuration.result" status)" == failed ]]
if grep -q forged "$work/result.tsv";then exit 1;fi
grep -q '|shell|blocked|' "$work/result.tsv"
# A malformed sidecar cannot turn a successful action into a trusted stage.
workflow_execute_stage() { printf '# dotfiles|stage-result|99\nkey|value\n' > "$4"; }
rm -rf "$context/runtime"
workflow_context_set "$context" session_path "$work/corrupt-workflow"
workflow_context_set "$context" results_path "$work/corrupt-result.tsv"
set +e
workflow_run "$context" > "$work/corrupt-log" 2>&1
code=$?
set -e
[[ "$code" == 65 ]]
grep -q '|configuration|failed|65|' "$work/corrupt-result.tsv"
grep -q '|shell|blocked|' "$work/corrupt-result.tsv"
printf 'Versioned contracts, pre-execution rejection and log-independent stage results passed.\n'
