# shellcheck shell=bash
# Public Unix orchestration API. All mutable state belongs to an explicit context.
workflow_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=workflow-profile.sh
source "$workflow_library_dir/workflow-profile.sh"
# shellcheck source=workflow-context.sh
source "$workflow_library_dir/workflow-context.sh"
# shellcheck source=workflow-stages.sh
source "$workflow_library_dir/workflow-stages.sh"
# shellcheck source=workflow-unix.sh
source "$workflow_library_dir/workflow-unix.sh"
# shellcheck source=install-items.sh
source "$workflow_library_dir/install-items.sh"
# shellcheck source=apply-items.sh
source "$workflow_library_dir/apply-items.sh"
# shellcheck source=mirrors.sh
source "$workflow_library_dir/mirrors.sh"

# shellcheck source=plan-explain.sh
source "$workflow_library_dir/plan-explain.sh"
# shellcheck source=workflow-review.sh
source "$workflow_library_dir/workflow-review.sh"
# shellcheck source=workflow-session.sh
source "$workflow_library_dir/workflow-session.sh"
# shellcheck source=execution-result.sh
source "$workflow_library_dir/execution-result.sh"


workflow_plan_configuration() {
  local context="$1" component output component_args=()
  while IFS= read -r component; do component_args+=("$component"); done < "$context/components"
  output="$(XDG_CONFIG_HOME="$(workflow_context_get "$context" config_home)" DOTFILES_BACKUP_DIR="$(workflow_context_get "$context" session_path)/configuration" \
    "$(workflow_context_get "$context" repo_root)/apply/apply.sh" --plan --no-mirrors "${component_args[@]}")" || return
  contract_read apply-plan "$output"
}
workflow_plan_mirrors() {
  local context="$1" output
  output="$(XDG_CONFIG_HOME="$(workflow_context_get "$context" config_home)" DOTFILES_BACKUP_DIR="$(workflow_context_get "$context" session_path)/mirrors" \
    "$(workflow_context_get "$context" repo_root)/apply/mirrors.sh" --initialize --plan --config "$(workflow_context_get "$context" mirror_config)")" || return
  contract_read apply-plan "$output"
}
workflow_assert_report_location() {
  local context="$1" path="$2" protected parent
  apply_safe_path "$path"
  [[ ! -e "$path" && ! -L "$path" ]] || { printf 'error: workflow output already exists: %s\n' "$path" >&2;return 1; }
  for protected in "$(workflow_context_get "$context" repo_root)" "$(workflow_context_get "$context" config_home)"; do
    if [[ "$path" == "$protected" || "$path" == "$protected/"* || "$protected" == "$path/"* ]];then printf 'error: workflow output overlaps repository or configuration: %s\n' "$path" >&2;return 1;fi
  done
  parent="$(apply_nearest_directory "$(dirname -- "$path")")"
  [[ -w "$parent" ]] || { printf 'error: workflow output parent is not writable: %s\n' "$parent" >&2;return 1; }
}
workflow_validate_plan_outputs() {
  local context="$1" plan="$2" component action source target rest output protected
  while IFS='|' read -r component action source target rest; do
    [[ -n "$component" && -n "$source" ]] || continue
    for output in "$(workflow_context_get "$context" session_path)" "$(workflow_context_get "$context" results_path)"; do
      [[ -n "$output" ]] || continue
      for protected in "$source" "$target"; do
        if [[ "$output" == "$protected" || "$output" == "$protected/"* || "$protected" == "$output/"* ]];then printf 'error: workflow output overlaps a planned file: %s\n' "$output" >&2;return 1;fi
      done
    done
  done <<< "$plan"
}
workflow_refresh_install_plan() {
  local context="$1" plan mode=normal
  plan="$(install_items_plan "$(workflow_context_get "$context" repo_root)/install/items" "$(workflow_context_get "$context" platform)" "$(workflow_context_get "$context" china_mirrors)" "$(workflow_context_get "$context" inside_wsl)" 0 "$(cat "$context/install.context")")" || return
  [[ ! -s "$context/resume_stages" ]] || mode=resume
  workflow_profile_install_plan "$(cat "$context/profile")" "$plan" "$(cat "$context/install.context")" "$mode"
}

workflow_preflight() {
  local context="$1" repo platform profile_name config_home backup_root session_id session results_path component definitions key value stage enabled reason prerequisite action combined
  repo="$(workflow_context_get "$context" repo_root)";platform="$(workflow_context_get "$context" platform)"
  profile_name="$(workflow_context_get "$context" profile_name)";session_id="$(workflow_context_get "$context" session_id)"
  [[ "$profile_name" =~ ^[a-z][a-z0-9-]*$ && "$session_id" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ && ${#session_id} -le 100 ]] || { printf 'error: invalid profile or session ID\n' >&2;return 2; }
  for key in dry_run plan_only china_mirrors inside_wsl assume_yes; do
    value="$(workflow_context_get "$context" "$key")"
    [[ "$value" == 0 || "$value" == 1 ]] || { printf 'error: invalid boolean context: %s\n' "$key" >&2;return 2; }
  done
  workflow_resume_prepare "$context"
  workflow_read_profile "$repo/workflow/profiles/$profile_name.conf" > "$context/profile"
  [[ "$(workflow_profile_value "$(cat "$context/profile")" wsl)" == none ]] || { printf 'error: Unix profiles require wsl=none\n' >&2;return 1; }
  workflow_stage_plan unix "$(cat "$context/profile")" "$(workflow_context_get "$context" only_stage)" "$(workflow_context_get "$context" from_stage)" "$(workflow_context_get "$context" china_mirrors)" > "$context/stages.plan"
  workflow_resume_filter "$context"
  config_home="$(apply_resolve_root "$(workflow_context_get "$context" config_home)")"
  backup_root="$(apply_resolve_root "$(workflow_context_get "$context" backup_root)")"
  session="$backup_root/workflow-$session_id"
  workflow_context_set "$context" config_home "$config_home"
  workflow_context_set "$context" session_path "$session"
  install_context_make "$platform" "$(workflow_context_get "$context" dry_run)" "$(workflow_context_get "$context" brew_cmd)" "$(workflow_context_get "$context" brew_prefix)" "$session/packages-backups" '' "$(workflow_context_get "$context" distro_id)" "$(workflow_context_get "$context" distro_codename)" > "$context/install.context"
  workflow_refresh_install_plan "$context" > "$context/install.plan"
  workflow_profile_components "$(cat "$context/profile")" "$(cat "$context/install.plan")" > "$context/components"
  definitions="$(apply_read_items "$repo/apply/items" unix)"
  while IFS= read -r component;do
    printf '%s\n' "$definitions" | awk -F '|' -v id="$component" '$1==id {found=1} END {exit !found}' || { printf 'error: unknown apply component: %s\n' "$component" >&2;return 1; }
  done < "$context/components"
  workflow_assert_report_location "$context" "$session"
  results_path="$(workflow_context_get "$context" results_path)"
  if [[ -n "$results_path" ]];then
    results_path="$(apply_resolve_root "$(dirname -- "$results_path")")/$(basename -- "$results_path")"
    [[ -d "$(dirname -- "$results_path")" ]] || { printf 'error: results parent must exist\n' >&2;return 1; }
    workflow_context_set "$context" results_path "$results_path"
    workflow_assert_report_location "$context" "$results_path"
    if [[ "$results_path" == "$session" || "$results_path" == "$session/"* || "$session" == "$results_path/"* ]];then printf 'error: report overlaps session directory\n' >&2;return 1;fi
  fi
  : > "$context/configuration.plan";: > "$context/mirrors.plan"
  while IFS='|' read -r stage enabled reason prerequisite action;do
    [[ "$enabled" == 1 ]] || continue
    case "$prerequisite" in
      packages)
        if [[ "$(workflow_context_get "$context" china_mirrors)" == 1 ]];then mirror_read_config "$(workflow_context_get "$context" mirror_config)" >/dev/null;fi
        if [[ "$(workflow_context_get "$context" dry_run)" == 0 && "$(workflow_context_get "$context" plan_only)" == 0 ]];then command -v sudo >/dev/null || { printf 'error: packages require sudo\n' >&2;return 1; };fi ;;
      configuration) workflow_plan_configuration "$context" > "$context/configuration.plan" ;;
      mirrors) workflow_plan_mirrors "$context" > "$context/mirrors.plan" ;;
      shell) workflow_preflight_shell "$context" ;;
      *) printf 'error: unsupported Unix prerequisite: %s\n' "$prerequisite" >&2;return 1 ;;
    esac
  done < "$context/stages.plan"
  combined="$(cat "$context/configuration.plan" "$context/mirrors.plan")"
  printf '%s\n' "$combined" | awk -F '|' '$3!="" && $10!="excluded" {if(seen[$4]++) bad=1} END {if(bad){print "error: overlapping configuration and mirror targets" > "/dev/stderr";exit 1}}'
  workflow_validate_plan_outputs "$context" "$combined"
  apply_validate_results "$results_path" "$combined"
  if [[ "$(workflow_context_get "$context" dry_run)" == 0 && "$(workflow_context_get "$context" plan_only)" == 0 ]] && printf '%s\n' "$combined" | awk -F '|' '$9=="sudo" {found=1} END {exit !found}';then
    command -v sudo >/dev/null || { printf 'error: selected file operations require sudo\n' >&2;return 1; }
  fi
}
workflow_print_plan() {
  local context="$1" stage enabled reason prerequisite action
  printf 'Workflow session: %s (profile=%s)\n' "$(workflow_context_get "$context" session_id)" "$(workflow_context_get "$context" profile_name)"
  while IFS='|' read -r stage enabled reason prerequisite action;do
    if [[ "$enabled" != 1 ]];then printf 'Stage %s: skipped (%s)\n' "$stage" "$reason";continue;fi
    printf '\nStage %s:\n' "$stage"
    case "$action" in
      packages) workflow_plan_preparation "$context";install_explain_plan "$(cat "$context/install.plan")" "$(workflow_context_get "$context" platform)" "$(workflow_profile_value "$(cat "$context/profile")" install)" "$(workflow_context_get "$context" repo_root)/install/items";contract_write install-plan "$(cat "$context/install.plan")" ;;
      configuration) apply_explain_plan "$(cat "$context/configuration.plan")";contract_write apply-plan "$(cat "$context/configuration.plan")" ;;
      mirrors) printf 'Lifecycle: initialize (preserve existing settings)\n';apply_explain_plan "$(cat "$context/mirrors.plan")";contract_write apply-plan "$(cat "$context/mirrors.plan")" ;;
      shell) printf 'Set login shell to Fish; recheck executable and account at execution.\n' ;;
      *) printf 'error: unsupported Unix action: %s\n' "$action" >&2;return 1 ;;
    esac
  done < "$context/stages.plan"
}
workflow_execute_stage() {
  local context="$1" action="$2" report="$3" metadata="${4:-}" repo config_home session component component_args=() args=() resume=0
  repo="$(workflow_context_get "$context" repo_root)";config_home="$(workflow_context_get "$context" config_home)";session="$(workflow_context_get "$context" session_path)"
  case "$action" in
    packages)
      if [[ "$(workflow_context_get "$context" china_mirrors)" == 1 ]];then mirror_prepare_install "$(workflow_context_get "$context" mirror_config)";fi
      workflow_refresh_install_plan "$context" > "$context/install.plan"
      workflow_prepare_packages "$context"
      workflow_refresh_install_plan "$context" > "$context/install.plan"
      if [[ -s "$context/resume_stages" ]];then resume=1;fi
      install_items_execute "$(cat "$context/install.plan")" "$(cat "$context/install.context")" "$report" "$resume" ;;
    configuration)
      while IFS= read -r component;do component_args+=("$component");done < "$context/components"
      args=(--no-mirrors --results "$report" --stage-result "$metadata")
      if [[ "$(workflow_context_get "$context" dry_run)" == 1 ]];then args+=(--dry-run);fi
      XDG_CONFIG_HOME="$config_home" DOTFILES_BACKUP_DIR="$session/configuration" "$repo/apply/apply.sh" "${args[@]}" "${component_args[@]}" ;;
    mirrors)
      args=(--initialize --results "$report" --stage-result "$metadata" --config "$(workflow_context_get "$context" mirror_config)")
      if [[ "$(workflow_context_get "$context" dry_run)" == 1 ]];then args+=(--dry-run);fi
      XDG_CONFIG_HOME="$config_home" DOTFILES_BACKUP_DIR="$session/mirrors" "$repo/apply/mirrors.sh" "${args[@]}" ;;
    shell) workflow_preflight_shell "$context";workflow_set_shell "$context" ;;
    *) printf 'error: unsupported Unix action: %s\n' "$action" >&2;return 1 ;;
  esac
}
workflow_main() {
  local context
  context="$(workflow_context_new "$@")"
  # Context lifetime belongs to this entry point, not any nested stage.
  # shellcheck disable=SC2064
  trap "$(printf 'rm -rf -- %q' "$context")" EXIT
  workflow_run "$context"
}
