# shellcheck shell=bash
# Native actions receive the context explicitly. Entry scripts do no stage work.
workflow_native_run() {
  local context="$1"
  shift
  command_run mutation "$(workflow_context_get "$context" dry_run)" 0 '' -- "$@"
}
workflow_confirm() {
  local context="$1" confirmation
  [[ "$(workflow_context_get "$context" platform)" == linux.* && "$(workflow_context_get "$context" assume_yes)" == 0 ]] || return 0
  [[ -t 0 ]] || { printf 'error: interactive workflow confirmation required; use --yes to confirm\n' >&2;return 1; }
  read -r -p "Run the selected dotfiles workflow ($(workflow_context_get "$context" profile_name))? [y/N] " confirmation
  [[ "$confirmation" == y || "$confirmation" == Y ]] || { printf 'Workflow cancelled.\n';return 1; }
}
workflow_preparation_request() {
  local context="$1" preview="$2"
  [[ -f "$context/install.plan" ]] || { printf 'error: missing current installation plan\n' >&2;return 1; }
  dotfiles_request install-preparation platform "$(workflow_context_get "$context" platform)" items "$(cat "$context/install.plan")" preview "$preview"
}
workflow_plan_preparation() {
  workflow_preparation_request "$1" 1
}
workflow_fish_path() {
  if [[ "$(workflow_context_get "$1" platform)" == macos ]]; then printf '%s/bin/fish\n' "$(workflow_context_get "$1" brew_prefix)"
  else command -v fish 2>/dev/null || printf '/usr/bin/fish\n';fi
}
workflow_set_shell() {
  local context="$1" user platform fish_path current_shell dry
  user="$(workflow_context_get "$context" user)";platform="$(workflow_context_get "$context" platform)"
  fish_path="$(workflow_fish_path "$context")";dry="$(workflow_context_get "$context" dry_run)"
  if [[ "$dry" == 0 ]]; then [[ -x "$fish_path" ]] || { printf 'error: Fish was not installed\n' >&2;return 1; };fi
  if ! grep -Fqx "$fish_path" /etc/shells; then
    if [[ "$dry" == 1 ]]; then printf 'DRY RUN: add %q to /etc/shells with sudo\n' "$fish_path"
    else printf '%s\n' "$fish_path" | sudo tee -a /etc/shells >/dev/null;fi
  fi
  if [[ "$platform" == macos ]]; then
    current_shell="$(dscl . -read "/Users/$user" UserShell | awk '$1=="UserShell:" {print $2}')"
    if [[ "$current_shell" != "$fish_path" ]]; then workflow_native_run "$context" chsh -s "$fish_path";else printf 'fish: already the default shell\n';fi
  else
    current_shell="$(getent passwd "$user" | cut -d: -f7)"
    if [[ "$(readlink -f "$current_shell")" != "$(readlink -f "$fish_path")" ]]; then workflow_native_run "$context" sudo chsh -s "$fish_path" "$user";else printf 'fish: already the default shell\n';fi
  fi
}
