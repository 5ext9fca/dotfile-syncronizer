#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/workflow.sh
source "$repo_root/lib/workflow.sh"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
context="$test_tmp/context";session="$test_tmp/old session,one";mkdir "$context" "$session"
workflow_context_set "$context" platform linux.apt
workflow_context_set "$context" profile_name linux
workflow_context_set "$context" china_mirrors 0
workflow_context_set "$context" dry_run 0
workflow_context_set "$context" only_stage ''
workflow_context_set "$context" from_stage ''
workflow_context_set "$context" resume_session ''
workflow_stage_plan unix $'shell=fish\nmirrors=initialize\nwsl=none' configuration '' 0 > "$context/stages.plan"
workflow_request_save "$context" "$session"
[[ "$(workflow_request_read "$session" | cut -d '|' -f4)" == configuration ]]
printf '%s\n' "$(contract_fields workflow-summary)" "old|linux|configuration|failed|23|0|$session/run.log|$session/configuration.tsv||command-failed|1||configuration" > "$session/workflow.tsv"
stage_result_init "$session/configuration.result" configuration "$session/configuration.tsv"
stage_result_artifact "$session/configuration.result" recovery_journal "$session/journal,one.tsv"
stage_result_finish "$session/configuration.result" 23 0 ''
workflow_context_set "$context" resume_session "$session"
workflow_context_set "$context" china_mirrors 1
workflow_resume_prepare "$context"
[[ "$(workflow_context_get "$context" china_mirrors)" == 0 ]]
workflow_stage_plan unix $'shell=fish\nmirrors=initialize\nwsl=none' '' '' 0 > "$context/stages.plan"
workflow_resume_filter "$context"
[[ "$(awk -F '|' '$2==1 {print $1}' "$context/stages.plan")" == configuration ]]
workflow_show_status "$session" > "$test_tmp/status"
grep -Fq 'exit=23' "$test_tmp/status"
grep -Fq "$session/journal,one.tsv" "$test_tmp/status"
grep -Fq -- '--resume' "$test_tmp/status"
# Failed/deferred dry runs offer another dry run, never an unusable resume command.
contract_save workflow-request 'linux.apt|linux|0|configuration||1' "$session/request.tsv"
for failure_code in 23 75 130;do
  stage_result_finish "$session/configuration.result" "$failure_code" 1 ''
  workflow_show_status "$session" > "$test_tmp/dry-status"
  grep -Fq -- 'original command with --dry-run' "$test_tmp/dry-status"
  grep -Fq 'same stage selection and mirror options' "$test_tmp/dry-status"
  if grep -Fq -- '--resume' "$test_tmp/dry-status";then exit 1;fi
done
if workflow_resume_prepare "$context" >/dev/null 2>&1;then exit 1;fi
contract_save workflow-request 'linux.apt|linux|0|configuration||0' "$session/request.tsv"
stage_result_finish "$session/configuration.result" 23 0 ''
workflow_context_set "$context" only_stage packages
if workflow_resume_prepare "$context" >/dev/null 2>&1;then exit 1;fi
workflow_context_set "$context" only_stage ''
workflow_context_set "$context" mirrors_explicit 1
if workflow_resume_prepare "$context" >/dev/null 2>&1;then exit 1;fi
workflow_context_set "$context" mirrors_explicit 0
workflow_context_set "$context" profile_explicit 1
if workflow_resume_prepare "$context" >/dev/null 2>&1;then exit 1;fi
workflow_context_set "$context" profile_explicit 0
contract_save workflow-request 'linux.apt|custom-profile|0|configuration||0' "$session/request.tsv"
workflow_resume_prepare "$context"
[[ "$(workflow_context_get "$context" profile_name)" == custom-profile ]]
sed 's/workflow-request|2/workflow-request|1/' "$session/request.tsv" > "$test_tmp/v1"
cp "$test_tmp/v1" "$session/request.tsv"
if workflow_resume_prepare "$context" > "$test_tmp/incompatible" 2>&1;then exit 1;fi
grep -q 'incompatible session' "$test_tmp/incompatible"
contract_save workflow-request 'linux.apt|linux|0|configuration||0' "$session/request.tsv"
# Sidecar wins over a stale failed summary. Completed sessions cannot be resumed.
stage_result_finish "$session/configuration.result" 0 0 ''
if workflow_resume_prepare "$context" >/dev/null 2>&1;then exit 1;fi
# Missing rows mean not started; preserve only the original selected stages.
contract_save workflow-request 'linux.apt|linux|0|packages,configuration,shell||0' "$session/request.tsv"
printf '%s\n' "$(contract_fields workflow-summary)" 'old|linux|packages|success|0|0|||||1||' > "$session/workflow.tsv"
workflow_resume_prepare "$context"
[[ "$(workflow_context_get "$context" resume_stages)" == configuration,shell ]]
# Dry-run sessions and incompatible hosts do not authorize a real continuation.
contract_save workflow-request 'linux.apt|linux|0|configuration||1' "$session/request.tsv"
if workflow_resume_prepare "$context" >/dev/null 2>&1;then exit 1;fi
contract_save workflow-request 'macos|macos|0|configuration||0' "$session/request.tsv"
if workflow_resume_prepare "$context" >/dev/null 2>&1;then exit 1;fi
# Item failures and literal artifact paths are visible without parsing logs.
contract_save workflow-request 'linux.apt|linux|0|packages||0' "$session/request.tsv"
contract_save install-result 'docker|failed|1|exit-23||||' "$session/packages.tsv"
printf '%s\n' "$(contract_fields workflow-summary)" "old|linux|packages|failed|23|0||$session/packages.tsv||command-failed|1||packages" > "$session/workflow.tsv"
workflow_show_status "$session" > "$test_tmp/status"
grep -Fq 'Item docker: failed (exit-23)' "$test_tmp/status"
if grep -q 'restore' "$test_tmp/status";then exit 1;fi
stage_result_init "$session/packages.result" packages "$session/packages.tsv"
printf 'corrupt\n' > "$session/packages.result"
if workflow_resume_prepare "$context" >/dev/null 2>&1;then exit 1;fi
printf 'Workflow resume selection and structured failure summary tests passed.\n'
