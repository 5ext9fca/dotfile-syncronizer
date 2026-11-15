# shellcheck shell=bash
# Human explanations are separate from the versioned machine-readable plans.
install_explain_plan() {
  local plan="$1" platform="$2" selection="${3:-all}" directory="${4:-}" record id dependencies selected_by source url repo release origin state method action reason order count=0 file available discovery methods preferred install_dependencies
  printf 'Installation selection: %s; platform=%s\n' "$selection" "$platform"
  while IFS= read -r record;do
    [[ -n "$record" ]] || continue
    id="$(install_field "$record" id)";method="$(install_field "$record" method)"
    action="$(install_field "$record" action)";reason="$(install_field "$record" reason)"
    order="$(install_field "$record" order)";dependencies="$(install_field "$record" depends_on)"
    selected_by=profile
    if [[ "$selection" != all && " $selection " != *" $id "* ]];then selected_by=dependency;fi
    source="$(install_field "$record" source_kind)";url="$(install_field "$record" source_url)"
    repo="$(install_field "$record" source_repo)";release="$(install_field "$record" source_release)"
    origin="$(install_field "$record" source_origin)";state="$(install_field "$record" state)"
    count=$((count+1))
    printf '  %s. %s: %s (%s); selected-by=%s, order=%s, method=%s\n' "$count" "$id" "$action" "$reason" "$selected_by" "$order" "$method"
    printf '     Packages: %s; depends-on: %s\n' "$(install_field "$record" packages)" "${dependencies:-none}"
    install_dependencies="$(install_field "$record" install_depends_on)"
    if [[ -n "$install_dependencies" ]];then printf '     Installation-only edges (omitted on skip unless independently selected): %s\n' "$install_dependencies";fi
    printf '     Source: %s (%s)' "$source" "$origin"
    if [[ -n "$url" ]];then printf '; url=%s' "$url";fi
    if [[ -n "$repo" ]];then printf '; repository=%s' "$repo";fi
    if [[ -n "$release" ]];then printf '; release=%s' "$release";fi
    if [[ -z "$url$repo$release" ]];then printf '; package-manager defaults';fi
    printf '\n'
    discovery="$(install_field "$record" discovery)"
    if [[ -n "$discovery" ]];then
      methods="$(install_field "$record" methods)";preferred="$(install_field "$record" preferred_method)"
      printf '     Discovery methods: %s; preferred install: %s\n' "${methods:-$method}" "${preferred:-$method}"
      printf '     Required paths by method (file-system only): %s\n' "$discovery"
    fi
    [[ -z "$state" ]] || printf '     Detected state: %s\n' "$state"
  done <<< "$plan"
  if [[ -n "$directory" ]];then
    available="$(install_items_read "$directory" "$platform")" || return
    for file in "$directory"/*.conf;do
      id="$(basename -- "$file" .conf)"
      if printf '%s\n' "$plan" | awk -F '|' -v id="$id" '$1==id {found=1} END {exit !found}';then continue;fi
      if printf '%s\n' "$available" | awk -F '|' -v id="$id" '$1==id {found=1} END {exit !found}';then reason=not-selected-by-profile
      else reason='platform-not-configured';fi
      printf '  %s: excluded (%s)\n' "$id" "$reason"
    done
  fi
  printf 'Presence checks describe installation only; this plan is a current-state preview.\n'
}
apply_explain_plan() {
  local plan="$1" component action source target backup _before _source_state _root privilege reason _version
  printf 'Configuration effects:\n'
  while IFS='|' read -r component action source target backup _before _source_state _root privilege reason _version;do
    [[ -n "$component" ]] || continue
    printf '  %s: %s %s (%s)\n' "$component" "$action" "$target" "$reason"
    [[ -z "$source" || "$reason" == excluded ]] || printf '     Source: %s\n' "$source"
    [[ -z "$backup" ]] || printf '     Existing target backup: %s\n' "$backup"
    [[ "$privilege" != sudo ]] || printf '     Requires elevated file access.\n'
  done <<< "$plan"
  printf 'Unchanged/excluded targets and unmanaged files are preserved.\n'
}
