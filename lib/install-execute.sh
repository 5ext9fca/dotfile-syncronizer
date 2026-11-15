# shellcheck shell=bash
# Each item runs in a fresh shell subshell with errexit enabled. Do not call a
# handler inside `if`: Bash would disable errexit throughout that handler.
install_items_execute() {
  local plan="$1" context="$2" results="${3:-}" resume="${4:-0}" record id method action reason started elapsed status code stopped=0
  local report='' result outcome restore_errexit=0 refreshed observed
  if [[ "$plan" == '# dotfiles|'* ]];then plan="$(contract_read install-plan "$plan")" || return;fi
  contract_validate_rows install-plan "$plan" || return
  install_execution_policy '*' install >/dev/null || return
  if [[ $- == *e* ]]; then restore_errexit=1; fi
  # Keep plan records off stdin: sudo and installers may need terminal input.
  while IFS= read -r -u 3 record; do
    [[ -n "$record" ]] || continue
    id="$(install_field "$record" id)";method="$(install_field "$record" method)"
    action="$(install_field "$record" action)";reason="$(install_field "$record" reason)"
    started=$SECONDS;code=0;observed=1
    if (( ! stopped )) && [[ "$resume" == 1 ]];then
      if [[ -n "$results" ]];then contract_save install-result "${report}$(install_result_row "$record" running 0 checking-current-state 0)" "$results";fi
      set +e
      refreshed="$(set -e;install_resume_record "$record" "$context")"
      code=$?
      if (( restore_errexit ));then set -e;fi
      if (( code == 0 ));then record="$refreshed";action="$(install_field "$record" action)";reason="$(install_field "$record" reason)";else observed=0;fi
    fi
    if (( code ));then
      outcome="$(execution_result "$code" "$(install_context "$context" 2)")";status="${outcome%%|*}";reason="${outcome#*|}";stopped=$code
    elif (( stopped )); then
      status=blocked;reason=previous-failure;observed=0
    elif [[ "$action" == skip ]]; then
      status=skipped
    else
      if [[ -n "$results" ]];then contract_save install-result "${report}$(install_result_row "$record" running 0 "$reason")" "$results";fi
      printf 'Install %s: %s (%s, source=%s)\n' "$id" "$action" "$method" "$(install_field "$record" source_origin)"
      # Capture only the status outside the subshell; handler output remains live.
      set +e
      ( set -e; install_dispatch "$method" "$record" "$context" )
      code=$?
      if (( restore_errexit )); then set -e; fi
      outcome="$(execution_result "$code" "$(install_context "$context" 2)")";status="${outcome%%|*}"
      if (( code ));then reason="${outcome#*|}";stopped=$code;fi
    fi
    elapsed=$((SECONDS-started))
    result="$(install_result_row "$record" "$status" "$elapsed" "$reason" "$observed")" || return
    report="${report}${result}"$'\n'
    if [[ -n "$results" ]];then contract_save install-result "${report%$'\n'}" "$results";fi
    printf 'Result %s: %s (%ss; %s)\n' "$id" "$status" "$elapsed" "$reason"
  done 3<<< "$plan"
  if [[ -n "$results" ]]; then contract_save install-result "${report%$'\n'}" "$results"; fi
  printf 'Installation item summary:\n%s' "$report"
  return "$stopped"
}

install_dispatch() {
  local method="$1" record="$2" context="$3"
  context="$(printf '%s\n' "$context" | cut -d '|' -f1-5)|$method|$(install_context "$context" 7)|$(install_context "$context" 8)"
  case "$method" in
    apt|dnf|pacman) install_native "$record" "$context" ;;
    docker-ce) install_docker_ce "$record" "$context" ;;
    cargo) install_cargo "$record" "$context" ;;
    pipx) install_pipx "$record" "$context" ;;
    brew|cask) install_brew "$record" "$context" ;;
    font-download) install_font_download "$record" "$context" ;;
    script) install_script "$record" "$context" ;;
    rustup) install_rustup "$record" "$context" ;;
    apt-or-snap) install_apt_or_snap "$record" "$context" ;;
    apt-repository|dnf-copr) install_repository "$record" "$context" ;;
    xcode|homebrew) install_bootstrap "$record" "$context" ;;
    *) printf 'error: unsupported execution method: %s\n' "$method" >&2; return 1 ;;
  esac
}

