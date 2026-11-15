# shellcheck shell=bash
# Pure policy: observations are supplied by the state adapter, never probed here.
install_decide() {
  local state="$1" mode="$2" probe_command="$3" command_present="$4" discovery="${5:-}" decision action reason decision_reason
  case "$mode" in normal|resume) ;; *) printf 'error: invalid installation decision mode\n' >&2;return 1 ;; esac
  if [[ "$state" == upgrade ]];then state=present;fi
  decision="$(install_probe_result "$state")" || return
  action="${decision%%|*}";reason="${decision#*|}"
  if [[ "$action" != skip && "$command_present" == 1 ]];then
    action=skip;reason=already-installed
    [[ "$mode" != resume ]] || state=present
  fi
  if [[ "$mode" == resume ]];then
    if [[ "$action" == skip ]];then reason=resume-already-installed
    elif [[ -z "$state" && -z "$probe_command" ]];then reason=resume-recheck-required;fi
  fi
  decision_reason="$reason"
  if [[ -n "$discovery" && -z "$state" ]];then decision_reason=no-discovery-match;fi
  printf '%s|%s|%s|%s\n' "$action" "$reason" "$state" "$decision_reason"
}
