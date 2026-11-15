# shellcheck shell=bash
stage_result_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=data-contract.sh
source "$stage_result_library_dir/data-contract.sh"
# shellcheck source=atomic-report.sh
source "$stage_result_library_dir/atomic-report.sh"
# shellcheck source=execution-result.sh
source "$stage_result_library_dir/execution-result.sh"
stage_result_read() {
  local rows
  rows="$(contract_read stage-result "$(cat "$1")")" || return
  printf '%s\n' "$rows" | awk -F '|' '
    $1 !~ /^(stage|status|exit_code|retry_stage|reason|report|recovery_journal|child_report)$/ {bad=1}
    $1!="recovery_journal" && $1!="child_report" && seen[$1]++ {bad=1}
    $1=="stage" && $2 !~ /^[a-z][a-z0-9-]*$/ {bad=1}
    $1=="status" && $2 !~ /^(running|success|planned|failed|deferred|interrupted)$/ {bad=1}
    $1=="exit_code" && $2 !~ /^[0-9]+$/ {bad=1}
    {rows[++n]=$0}
    END {split("stage status exit_code retry_stage reason report",required," ");for(i=1;i<=6;i++) if(!seen[required[i]]) bad=1;if(bad) exit 1;for(i=1;i<=n;i++) print rows[i]}
  '
}
stage_result_publish() {
  local document
  document="$(contract_write stage-result "$2")" || return
  printf '%s\n' "$document" | atomic_report_write "$1" "${3:-replace}"
}
stage_result_init() {
  local path="$1" stage="$2" report="$3" rows
  rows="$(printf 'stage|%s\nstatus|running\nexit_code|0\nretry_stage|%s\nreason|started\nreport|%s' "$stage" "$stage" "$report")"
  stage_result_publish "$path" "$rows" create
}
stage_result_ensure() {
  [[ -n "$1" ]] || return 0
  if [[ -f "$1" ]];then stage_result_read "$1" >/dev/null
  else stage_result_init "$1" "$2" "$3";fi
}
stage_result_get() { stage_result_read "$1" | awk -F '|' -v key="$2" '$1==key {print $2}'; }
stage_result_artifact() {
  local path="$1" key="$2" value="$3" rows
  [[ -n "$path" ]] || return 0
  [[ "$key" == recovery_journal || "$key" == child_report ]] || return 1
  [[ "$value" != *'|'* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] || return 1
  rows="$(stage_result_read "$path")" || return
  if printf '%s\n' "$rows" | grep -Fxq "$key|$value";then return;fi
  stage_result_publish "$path" "$rows"$'\n'"$key|$value"
}
stage_result_finish() {
  local path="$1" code="$2" dry="$3" report="$4" outcome stage rows retry
  outcome="$(execution_result "$code" "$dry")" || return
  stage="$(stage_result_get "$path" stage)" || return
  rows="$(stage_result_read "$path" | awk -F '|' '$1=="stage" || $1=="recovery_journal" || $1=="child_report"')" || return
  retry='';[[ "$code" == 0 ]] || retry="$stage"
  [[ -f "$report" ]] || report=''
  rows="$rows"$'\n'"$(printf 'status|%s\nexit_code|%s\nreason|%s\nretry_stage|%s\nreport|%s' "${outcome%%|*}" "$code" "${outcome#*|}" "$retry" "$report")"
  stage_result_publish "$path" "$rows"
}
