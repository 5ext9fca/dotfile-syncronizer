# shellcheck shell=bash
apply_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=command.sh
source "$apply_library_dir/command.sh"
# shellcheck source=atomic-report.sh
source "$apply_library_dir/atomic-report.sh"
# shellcheck source=stage-result.sh
source "$apply_library_dir/stage-result.sh"
# shellcheck source=apply-fs.sh
source "$apply_library_dir/apply-fs.sh"
# shellcheck source=desktop-fonts.sh
source "$apply_library_dir/desktop-fonts.sh"
# shellcheck source=apply-plan.sh
source "$apply_library_dir/apply-plan.sh"
# shellcheck source=../apply/handlers/files.sh
source "$apply_library_dir/../apply/handlers/files.sh"

apply_session_path() {
  local base="$1" candidate suffix=0
  candidate="$base/apply-$(date +%Y%m%d-%H%M%S)-$$"
  while apply_exists "$candidate";do suffix=$((suffix+1));candidate="$base/apply-$(date +%Y%m%d-%H%M%S)-$$.$suffix";done
  printf '%s\n' "$candidate"
}

apply_validate_plan() {
  printf '%s\n' "$1" | awk -F '|' '
    /^$/ {next}
    NF!=11 || $11!="1" || $2 !~ /^(mkdir|hardlink|copy|skip)$/ {bad=1;next}
    $10!="excluded" {if(seen[$4]++) bad=1}
    END {if(bad){print "error: malformed plan or overlapping deployment/mirror targets" > "/dev/stderr";exit 1}}
  '
}

apply_validate_results() {
  local results="$1" plan="$2" path parent component action source target rest
  [[ -n "$results" ]] || return 0
  apply_safe_path "$results" || return
  parent="$(dirname -- "$results")"
  [[ -d "$parent" && -w "$parent" && ! -d "$results" && ! -L "$results" ]] || { printf 'error: result path is not a writable regular-file destination\n' >&2;return 1; }
  if [[ -e "$results" && ! -w "$results" ]];then printf 'error: result file is not writable\n' >&2;return 1;fi
  path="$(cd -- "$parent" && pwd -P)/$(basename -- "$results")"
  while IFS='|' read -r component action source target rest;do
    [[ -n "$component" ]] || continue
    if [[ "$path" == "$source" || ( -n "$source" && "$path" == "$source/"* ) || "$path" == "$target" || "$path" == "$target/"* || "$target" == "$path/"* ]] || { [[ -e "$results" ]] && { [[ -n "$source" && "$results" -ef "$source" ]] || [[ "$results" -ef "$target" ]]; }; };then
      printf 'error: result file overlaps a deployment source or destination\n' >&2;return 1
    fi
  done <<< "$plan"
}

apply_execute_plan_unlocked() {
  local plan="$1" session="$2" dry="$3" results_path="${4:-}" metadata="${5:-}" record component action source target backup _before _source_state _root _privilege reason _version sequence=0 failed=0 status started elapsed report='' code restore_errexit=0
  if [[ "$plan" == '# dotfiles|'* ]];then plan="$(contract_read apply-plan "$plan")" || return;fi
  contract_validate_rows apply-plan "$plan" || return
  apply_validate_plan "$plan" || return
  apply_validate_results "$results_path" "$plan" || return
  apply_validate_results "$metadata" "$plan" || return
  if [[ -n "$metadata" && -n "$results_path" ]] && { [[ "$metadata" == "$results_path" ]] || [[ "$metadata" -ef "$results_path" ]]; };then printf 'error: stage result overlaps detail report\n' >&2;return 1;fi
  stage_result_ensure "$metadata" apply "$results_path" || return
  [[ $- != *e* ]] || restore_errexit=1
  if [[ "$dry" == 0 && -n "$plan" ]];then
    [[ ! -e "$session" && ! -L "$session" ]] || { printf 'error: session already exists\n' >&2;return 1; }
    mkdir -p "$session"
    printf '# dotfiles-apply-journal-v1\n' > "$session/journal.tsv"
    stage_result_artifact "$metadata" recovery_journal "$session/journal.tsv"
    printf 'Recovery journal: %s/journal.tsv\n' "$session"
  fi
  while IFS= read -r record;do
    [[ -n "$record" ]] || continue
    sequence=$((sequence+1));started=$SECONDS
    IFS='|' read -r component action source target backup _before _source_state _root _privilege reason _version <<< "$record"
    if [[ "$action" == skip ]];then status=skipped
    elif (( failed ));then status=blocked
    elif [[ "$dry" == 1 ]];then
      status=planned
      [[ -z "$backup" ]] || printf 'DRY RUN: back up %q to %q\n' "$target" "$backup"
      printf 'DRY RUN: %s %q -> %q\n' "$action" "$source" "$target"
    else
      set +e
      apply_transaction "$record" "$session/journal.tsv" "$sequence"
      code=$?
      if (( restore_errexit ));then set -e;fi
      if (( code ));then status=failed;failed=$code;else status=success;fi
    fi
    elapsed=$((SECONDS-started))
    report="${report}${component}|${action}|${target}|${backup}|${status}|${elapsed}|${reason}"$'\n'
    printf '%s: %s (%s; %ss)\n' "$target" "$status" "$reason" "$elapsed"
  done <<< "$plan"
  if [[ -n "$results_path" ]];then contract_save apply-result "${report%$'\n'}" "$results_path";fi
  printf '%s' "$report" | awk -F '|' '
    NF { seen[$1]=1;time[$1]+=$6; if($5=="failed") failed[$1]++;else if($5=="blocked") blocked[$1]++;else if($5=="skipped") skipped[$1]++;else if($2=="mkdir") dirs[$1]++;else if($7=="replace") replaced[$1]++;else created[$1]++ }
    END { for(c in seen) printf "%s: new=%d replaced=%d skipped=%d directories=%d failed=%d blocked=%d elapsed=%ds\n",c,created[c],replaced[c],skipped[c],dirs[c],failed[c],blocked[c],time[c] }
  ' | LC_ALL=C sort
  if [[ -n "$metadata" ]];then stage_result_finish "$metadata" "$failed" "$dry" "$results_path";fi
  return "$failed"
}
# shellcheck source=apply-restore.sh
source "$apply_library_dir/apply-restore.sh"

# shellcheck source=deployment-lock.sh
source "$apply_library_dir/deployment-lock.sh"
apply_execute_plan() {
  local plan="$1"
  shift
  if [[ "$plan" == '# dotfiles|'* ]];then plan="$(contract_read apply-plan "$plan")" || return;fi
  contract_validate_rows apply-plan "$plan" || return
  apply_validate_plan "$plan" || return
  deployment_run "$2" apply_execute_plan_unlocked "$plan" "$@"
}
apply_restore() { deployment_run "$2" apply_restore_unlocked "$@"; }
