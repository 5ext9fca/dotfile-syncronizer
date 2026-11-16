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


workflow_preflight() {
  dotfiles_request workflow-preflight-native style unix native_shell "$BASH" directory "$1"
}
workflow_print_plan() {
  local context="$1" stage enabled reason _prerequisite action
  printf 'Workflow session: %s (profile=%s)\n' "$(workflow_context_get "$context" session_id)" "$(workflow_context_get "$context" profile_name)"
  while IFS='|' read -r stage enabled reason _prerequisite action;do
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
  local context="$1" action="$2" report="$3" metadata="${4:-}" repo config_home session component component_args=() args=()
  repo="$(workflow_context_get "$context" repo_root)";config_home="$(workflow_context_get "$context" config_home)";session="$(workflow_context_get "$context" session_path)"
  case "$action" in
    packages)
      dotfiles_request workflow-packages-native style unix native_shell "$BASH" directory "$context" report "$report" ;;
    configuration)
      while IFS= read -r component;do component_args+=("$component");done < "$context/components"
      args=(--no-mirrors --results "$report" --stage-result "$metadata")
      if [[ "$(workflow_context_get "$context" dry_run)" == 1 ]];then args+=(--dry-run);fi
      XDG_CONFIG_HOME="$config_home" DOTFILES_BACKUP_DIR="$session/configuration" "$repo/apply/apply.sh" "${args[@]}" "${component_args[@]}" ;;
    mirrors)
      args=(--initialize --results "$report" --stage-result "$metadata" --config "$(workflow_context_get "$context" mirror_config)")
      if [[ "$(workflow_context_get "$context" dry_run)" == 1 ]];then args+=(--dry-run);fi
      XDG_CONFIG_HOME="$config_home" DOTFILES_BACKUP_DIR="$session/mirrors" "$repo/apply/mirrors.sh" "${args[@]}" ;;
    shell) dotfiles_request workflow-shell-native native_shell "$BASH" directory "$context" ;;
    *) printf 'error: unsupported Unix action: %s\n' "$action" >&2;return 1 ;;
  esac
}
workflow_main() {
  dotfiles_python_init || return
  local context
  context="$(workflow_context_new "$@")"
  # Context lifetime belongs to this entry point, not any nested stage.
  # shellcheck disable=SC2064
  trap "$(printf 'rm -rf -- %q' "$context")" EXIT
  workflow_run "$context"
}
