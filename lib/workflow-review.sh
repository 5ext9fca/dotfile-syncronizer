# shellcheck shell=bash
workflow_review_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=stage-result.sh
source "$workflow_review_library_dir/stage-result.sh"

# shellcheck source=install-report.sh
source "$workflow_review_library_dir/install-report.sh"

workflow_request_read() {
  local rows
  rows="$(contract_read workflow-request "$(cat "$1/request.tsv")")" || return
  printf '%s\n' "$rows" | awk -F '|' '
    NR!=1 || $1!~/^(linux\.(apt|dnf|pacman)|macos|windows)$/ || $2!~/^[a-z][a-z0-9-]*$/ || $3!~/^[01]$/ || $6!~/^[01]$/ {bad=1}
    {n=split($4,stages,",");for(i=1;i<=n;i++) if(stages[i]!~/^[a-z][a-z0-9-]*$/ || seen[stages[i]]++) bad=1}
    END {if(NR!=1 || bad) exit 1;print}'
}
workflow_summary_read() {
  local rows
  rows="$(contract_read workflow-summary "# dotfiles|workflow-summary|1"$'\n'"$(cat "$1/workflow.tsv")")" || return
  printf '%s\n' "$rows" | awk -F '|' '
    NF {if($3!~/^[a-z][a-z0-9-]*$/ || seen[$3]++ || $4!~/^(pending|running|success|planned|skipped|failed|blocked|deferred|interrupted)$/ || $5!~/^[0-9]+$/ || $11!="1") bad=1; rows[++n]=$0}
    END {if(bad) exit 1;for(i=1;i<=n;i++) print rows[i]}'
}
workflow_review_rows() {
  local session="$1" rows row stage metadata status code reason report request selected
  rows="$(workflow_summary_read "$session")" || return
  while IFS= read -r row;do
    [[ -n "$row" ]] || continue
    stage="$(printf '%s\n' "$row" | cut -d '|' -f3)"
    metadata="$session/$stage.result"
    if [[ -f "$metadata" ]];then
      stage_result_read "$metadata" >/dev/null || return
      [[ "$(stage_result_get "$metadata" stage)" == "$stage" ]] || return 1
      status="$(stage_result_get "$metadata" status)";code="$(stage_result_get "$metadata" exit_code)"
      reason="$(stage_result_get "$metadata" reason)";report="$(stage_result_get "$metadata" report)"
      # Sidecars carry authoritative artifact/status data; keep useful exception
      # messages from the summary when it describes the same result.
      printf '%s\n' "$row" | awk -F '|' -v OFS='|' -v status="$status" -v code="$code" -v reason="$reason" -v report="$report" '{if($4!=status || $10=="") $10=reason;$4=status;$5=code;$8=report;print}'
    else printf '%s\n' "$row";fi
  done <<< "$rows"
  if [[ -f "$session/request.tsv" ]];then
    request="$(workflow_request_read "$session")" || return
    selected="$(printf '%s\n' "$request" | cut -d '|' -f4)"
    while IFS= read -r stage;do
      if ! printf '%s\n' "$rows" | awk -F '|' -v stage="$stage" '$3==stage {found=1} END {exit !found}';then
        printf '|%s|%s|pending|0|0||||not-started|1||%s\n' "$(printf '%s\n' "$request" | cut -d '|' -f2)" "$stage" "$stage"
      fi
    done < <(printf '%s\n' "$selected" | tr ',' '\n')
  fi
}
workflow_request_save() {
  local context="$1" directory="$2" selected parent=''
  selected="$(awk -F '|' '$2==1 {print $1}' "$context/stages.plan" | paste -sd ',' -)"
  [[ -n "$selected" ]] || return 0
  [[ ! -f "$context/resume_session" ]] || parent="$(workflow_context_get "$context" resume_session)"
  contract_save workflow-request "$(workflow_context_get "$context" platform)|$(workflow_context_get "$context" profile_name)|$(workflow_context_get "$context" china_mirrors)|$selected|$parent|$(workflow_context_get "$context" dry_run)" "$directory/request.tsv"
}
workflow_resume_prepare() {
  local context="$1" session request platform profile mirrors selected parent dry rows remaining stage status failed=0
  [[ -f "$context/resume_session" ]] || return 0
  session="$(workflow_context_get "$context" resume_session)";[[ -n "$session" ]] || return 0
  [[ -z "$(workflow_context_get "$context" only_stage)" && -z "$(workflow_context_get "$context" from_stage)" && "$(cat "$context/mirrors_explicit" 2>/dev/null || printf 0)" != 1 ]] || { printf 'error: --resume cannot be combined with stage or mirror selectors\n' >&2;return 2; }
  session="$(cd -- "$session" && pwd -P)" || return
  request="$(workflow_request_read "$session")" || { printf 'error: session has no valid resume request; use --from-stage manually\n' >&2;return 2; }
  IFS='|' read -r platform profile mirrors selected parent dry <<< "$request"
  [[ "$platform" == "$(workflow_context_get "$context" platform)" && "$profile" == "$(workflow_context_get "$context" profile_name)" && "$dry" == 0 ]] || { printf 'error: resume requires a real session on the same platform/profile\n' >&2;return 2; }
  rows="$(workflow_review_rows "$session")" || return
  remaining=''
  while IFS= read -r stage;do
    status="$(printf '%s\n' "$rows" | awk -F '|' -v stage="$stage" '$3==stage {print $4}')"
    if [[ "$status" != success ]];then failed=1;fi
    if (( failed ));then remaining="${remaining}${remaining:+,}$stage";fi
  done < <(printf '%s\n' "$selected" | tr ',' '\n')
  [[ -n "$remaining" ]] || { printf 'error: session already completed; nothing to resume\n' >&2;return 2; }
  workflow_context_set "$context" china_mirrors "$mirrors"
  workflow_context_set "$context" resume_session "$session"
  workflow_context_set "$context" resume_stages "$remaining"
}
workflow_resume_filter() {
  local context="$1" stages selected stage
  [[ -f "$context/resume_stages" ]] || return 0
  selected="$(workflow_context_get "$context" resume_stages)"
  while IFS= read -r stage;do
    awk -F '|' -v stage="$stage" '$1==stage {found=1} END {exit !found}' "$context/stages.plan" || { printf 'error: resume stage no longer exists: %s\n' "$stage" >&2;return 2; }
  done < <(printf '%s\n' "$selected" | tr ',' '\n')
  stages="$(awk -F '|' -v OFS='|' -v selected=",$selected," '{if(index(selected,"," $1 ",")==0){$2=0;$3="resume-selection"}print}' "$context/stages.plan")"
  printf '%s\n' "$stages" > "$context/stages.plan"
}
workflow_show_status() {
  local session="$1" rows row stage status code reason log report metadata key value retry='' kind details journal child request
  rows="$(workflow_review_rows "$session")" || return
  while IFS= read -r row;do
    [[ -n "$row" ]] || continue
    IFS='|' read -r _ _ stage status code _ log report journal reason _ child _ <<< "$row"
    printf '%s: %s (exit=%s, %s)\n' "$stage" "$status" "$code" "$reason"
    case "$status" in
      failed|deferred|interrupted|running|blocked|pending) [[ -n "$retry" ]] || retry="$stage" ;;
    esac
    [[ "$status" != deferred ]] || printf '  Action: complete the manual prerequisite, then retry.\n'
    [[ "$status" != running ]] || printf '  Action: incomplete record; verify the previous run has stopped before retrying.\n'
    [[ -z "$log" ]] || printf '  Log: %s\n' "$log"
    [[ -z "$report" ]] || printf '  Detail report: %s\n' "$report"
    if [[ -n "$report" && -f "$report" ]];then
      kind="$(head -n 1 "$report" | cut -d '|' -f2)"
      case "$kind" in
        install-result|apply-result|git-result)
          if [[ "$kind" == install-result ]];then details="$(install_result_read "$(cat "$report")")" || return
          else details="$(contract_read "$kind" "$(cat "$report")")" || return;fi
          case "$kind" in
            install-result) install_result_show "$details" ;;
            apply-result) printf '%s\n' "$details" | awk -F '|' '$5~/^(failed|deferred|interrupted)$/ {printf "  Component %s: %s (%s), target=%s\n",$1,$5,$7,$3}' ;;
          esac ;;
      esac
    fi
    metadata="$session/$stage.result"
    if [[ -f "$metadata" ]];then
      while IFS='|' read -r key value;do
        case "$key" in
          recovery_journal) printf '  Recovery journal (inspect if configuration recovery is needed): %s\n' "$value" ;;
          child_report) printf '  Child report: %s\n' "$value" ;;
        esac
      done < <(stage_result_read "$metadata")
    else
      [[ -z "$journal" ]] || printf '  Legacy recovery references: %s\n' "$journal"
      [[ -z "$child" ]] || printf '  Legacy child reports: %s\n' "$child"
    fi
  done <<< "$rows"
  if [[ -n "$retry" ]];then
    if [[ -f "$session/request.tsv" ]];then
      request="$(workflow_request_read "$session")" || return
      if [[ "$(printf '%s\n' "$request" | cut -d '|' -f6)" == 1 ]];then
        printf 'Recheck after resolving the cause: rerun the original command with --dry-run and the same stage selection and mirror options (dry-run sessions cannot be resumed).\n'
      else
        printf 'Resume after resolving the cause: ./install/%s.sh --resume %q\n' "$(printf '%s\n' "$request" | cut -d '|' -f1 | cut -d '.' -f1)" "$session"
      fi
    else printf 'Retry after resolving the cause: --from-stage %s (legacy session without saved selection).\n' "$retry";fi
  fi
}
