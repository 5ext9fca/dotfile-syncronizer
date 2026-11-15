# shellcheck shell=bash
# A private directory carries scalar inputs and computed plans. No eval,
# associative arrays, exported variables, or caller dynamic scope is required.
workflow_context_new() {
  local directory key value seen=' '
  (( $# % 2 == 0 )) || { printf 'error: context requires key/value pairs\n' >&2; return 2; }
  directory="$(mktemp -d)" || return
  while (( $# )); do
    key="$1";value="$2";shift 2
    case "$key" in distro_id|distro_codename|resume_session|mirrors_explicit|repo_root|platform|profile_name|dry_run|plan_only|results_path|only_stage|from_stage|session_id|config_home|backup_root|brew_cmd|brew_prefix|assume_yes|user|china_mirrors|inside_wsl|mirror_config) ;;
      *) printf 'error: unknown context field: %s\n' "$key" >&2;rm -rf "$directory";return 2 ;;
    esac
    if [[ "$seen" == *" $key "* || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
      printf 'error: duplicate or invalid context field: %s\n' "$key" >&2;rm -rf "$directory";return 2
    fi
    seen="$seen$key "
    printf '%s\n' "$value" > "$directory/$key"
  done
  for key in repo_root platform profile_name dry_run plan_only results_path only_stage from_stage session_id config_home backup_root brew_cmd brew_prefix assume_yes user china_mirrors inside_wsl mirror_config; do
    if [[ ! -f "$directory/$key" ]]; then printf 'error: missing context field: %s\n' "$key" >&2;rm -rf "$directory";return 2;fi
  done
  for key in distro_id distro_codename;do
    [[ -f "$directory/$key" ]] || printf '\n' > "$directory/$key"
  done
  printf '%s\n' "$directory"
}
workflow_context_get() {
  [[ "$2" =~ ^[a-z][a-z0-9_.-]*$ ]] || return 2
  cat "$1/$2"
}
workflow_context_set() {
  [[ "$2" =~ ^[a-z][a-z0-9_.-]*$ ]] || return 2
  printf '%s\n' "$3" > "$1/$2"
}
workflow_will_install() {
  local context="$1" id="$2"
  awk -F '|' '$2==1 && $5=="packages" {found=1} END {exit !found}' "$context/stages.plan" || return 1
  awk -F '|' -v id="$id" '$1==id {found=1} END {exit !found}' "$context/install.plan"
}
