# shellcheck shell=bash
# Resolve sources, environment selection and read-only presence checks once, before any mutation.
# inspect=0 produces reproducible offline plans for any supported platform.
install_items_plan() {
  local directory="$1" platform="$2" mirrors="${3:-1}" wsl="${4:-0}" inspect="${5:-1}" context="${6:-}"
  local raw record url mirror action reason origin state environments environment provider decision_reason
  raw="$(install_items_read "$directory" "$platform")" || return
  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    mirror="$(install_field "$record" mirror_url)"
    url="$(install_field "$record" source_url)"
    action=install reason=requested origin=config state='' decision_reason=offline-preferred-method
    if [[ "$mirrors" == 1 && -n "$mirror" ]]; then
      url="$mirror";origin=mirror
    fi
    environment=native;[[ "$wsl" != 1 ]] || environment=wsl
    environments="$(install_field "$record" environments)";provider="$(install_field "$record" wsl_provider)"
    if [[ "$wsl" == 1 && -n "$provider" ]];then
      action=skip;reason="provided-by-host:$provider";state="provider:$provider"
    elif [[ -n "$environments" && " $environments " != *" $environment "* ]];then
      action=skip;reason="environment-not-selected:$environment"
    elif [[ "$inspect" == 1 ]]; then
      record="$(install_evaluate_record "$record" "$context" normal)" || return
      action="$(install_field "$record" action)";reason="$(install_field "$record" reason)";state="$(install_field "$record" state)"
    fi
    if [[ "$action" == skip && "$reason" == provided-by-host:* || "$reason" == environment-not-selected:* ]];then decision_reason="$reason"
    elif [[ "$inspect" == 1 ]];then decision_reason="$(install_field "$record" decision_reason)";fi
    install_record_update "$record" source_url "$url" action "$action" reason "$reason" source_origin "$origin" state "$state" decision_reason "$decision_reason" schema_version "$(contract_version install-plan)"
  done <<< "$raw"
}

