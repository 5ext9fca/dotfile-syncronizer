# shellcheck shell=bash
# Session lifetime and durable stage reports.
# shellcheck source=atomic-report.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/atomic-report.sh"
workflow_run_unlocked() {
  local context="$1" stage enabled _prerequisite action code status stopped=0 started log report journal summary report_dir persistent=0 reason session session_id profile_name dry results_path outcome retry_stage='' child_report metadata
  workflow_preflight "$context"
  if [[ "$(workflow_context_get "$context" plan_only)" == 1 ]];then workflow_print_plan "$context";return;fi
  workflow_confirm "$context"
  session="$(workflow_context_get "$context" session_path)";session_id="$(workflow_context_get "$context" session_id)";profile_name="$(workflow_context_get "$context" profile_name)"
  dry="$(workflow_context_get "$context" dry_run)";results_path="$(workflow_context_get "$context" results_path)"
  report_dir="$context/runtime";mkdir "$report_dir"
  if [[ "$dry" == 0 || -n "$results_path" ]];then persistent=1;mkdir -p "$(dirname -- "$session")";mkdir "$session";report_dir="$session";fi
  workflow_request_save "$context" "$report_dir"
  summary="$report_dir/workflow.tsv"
  printf 'session|profile|stage|status|exit_code|elapsed_seconds|log|report|recovery_journal|reason|schema_version|child_report|retry_stage\n' | atomic_report_write "$summary"
  if [[ -n "$results_path" ]];then atomic_report_write "$results_path" create < "$summary";fi
  cp "$summary" "$report_dir/events.tsv"
  cp "$summary" "$report_dir/completed.tsv"
  printf 'Workflow session: %s\n' "$session_id"
  # Read plan data separately so stage commands retain the caller's stdin.
  while IFS='|' read -r -u 3 stage enabled reason _prerequisite action;do
    code=0;started=$SECONDS;child_report='';journal='';log='';report=''
    if [[ "$enabled" != 1 ]];then status=skipped
    elif (( stopped ));then status=blocked;reason=previous-stage-failed
    else
      log="$report_dir/$stage.log";report="$report_dir/$stage.tsv"
      printf '%s|%s|%s|running|0|0|%s|%s||started|1||%s\n' "$session_id" "$profile_name" "$stage" "$log" "$report" "$stage" >> "$report_dir/events.tsv"
      { cat "$report_dir/completed.tsv";tail -n 1 "$report_dir/events.tsv"; } | atomic_report_write "$summary"
      if [[ -n "$results_path" ]];then atomic_report_write "$results_path" < "$summary";fi
      metadata="$report_dir/$stage.result"
      stage_result_init "$metadata" "$stage" "$report"
      set +e
      (set -e;workflow_execute_stage "$context" "$action" "$report" "$metadata") 2>&1 | tee "$log"
      code=$?
      set -e
      if stage_result_read "$metadata" >/dev/null;then
        stage_result_finish "$metadata" "$code" "$dry" "$report"
        child_report="$(stage_result_get "$metadata" child_report | paste -sd ',' -)"
        journal="$(stage_result_get "$metadata" recovery_journal | paste -sd ',' -)"
      else
        printf 'error: invalid stage result: %s\n' "$metadata" >&2;code=65
      fi
      outcome="$(execution_result "$code" "$dry")";status="${outcome%%|*}"
      if (( code ));then reason="${outcome#*|}";stopped=$code;retry_stage="$stage";fi
      [[ -f "$report" ]] || report=''
      if (( ! persistent ));then log='';report='';fi
    fi
    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|1|%s|%s\n' "$session_id" "$profile_name" "$stage" "$status" "$code" "$((SECONDS-started))" "$log" "$report" "$journal" "$reason" "$child_report" "$retry_stage" >> "$report_dir/completed.tsv"
    atomic_report_write "$summary" < "$report_dir/completed.tsv"
    if [[ -n "$results_path" ]];then atomic_report_write "$results_path" < "$summary";fi
    tail -n 1 "$summary" >> "$report_dir/events.tsv"
    printf 'Stage %s: %s\n' "$stage" "$status"
  done 3< "$context/stages.plan"
  if (( persistent ));then printf 'Workflow report: %s\n' "$summary";fi
  if (( stopped ));then
    if (( persistent ));then printf 'Inspect failure: bash workflow/status.sh %q\n' "$session" >&2;fi
    if (( persistent )) && [[ "$dry" == 0 ]];then printf 'After resolving the cause, continue with --resume %q; current state is checked again.\n' "$session" >&2
    else printf 'Retry with --from-stage STAGE or --only-stage STAGE; current state is checked again.\n' >&2;fi
  fi
  return "$stopped"
}

workflow_run() {
  local dry
  dry="$(workflow_context_get "$1" dry_run)"
  if [[ "$(workflow_context_get "$1" plan_only)" == 1 ]];then dry=1;fi
  deployment_run "$dry" workflow_run_unlocked "$1"
}
