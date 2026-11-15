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
workflow_packages_need() {
  local context="$1" methods="$2" record method
  [[ -f "$context/install.plan" ]] || { printf 'error: missing current installation plan\n' >&2;return 2; }
  while IFS= read -r record;do
    [[ -n "$record" ]] || continue
    [[ "$(install_field "$record" action)" != skip ]] || continue
    method="$(install_field "$record" method)"
    # A snap recipe does not consume APT metadata.
    if [[ "$method" == apt-or-snap && "$(install_field "$record" state)" == snap:* ]];then continue;fi
    [[ " $methods " != *" $method "* ]] || return 0
  done < "$context/install.plan"
  return 1
}
workflow_plan_preparation() {
  local context="$1"
  case "$(workflow_context_get "$context" platform)" in
    linux.apt)
      if workflow_packages_need "$context" 'apt apt-repository apt-or-snap';then printf 'Preparation: sudo apt-get update\n';fi ;;
    linux.pacman)
      if workflow_packages_need "$context" rustup;then printf 'Preparation: remove conflicting rust-analyzer if installed.\n';fi
      if workflow_packages_need "$context" pacman;then printf 'Preparation: sudo pacman -Syu --noconfirm (required for pending native installation).\n';fi ;;
    linux.dnf) printf 'Preparation: DNF refreshes metadata only for pending installation.\n' ;;
    macos) printf 'Preparation: only missing Xcode/Homebrew prerequisites; Xcode GUI initialization may defer execution.\n' ;;
  esac
}
workflow_prepare_packages() {
  local context="$1" installed
  [[ -f "$context/install.plan" ]] || { printf 'error: missing current installation plan\n' >&2;return 1; }
  case "$(workflow_context_get "$context" platform)" in
    linux.apt)
      if workflow_packages_need "$context" 'apt apt-repository apt-or-snap';then workflow_native_run "$context" sudo apt-get update;fi ;;
    linux.pacman)
      if workflow_packages_need "$context" rustup;then
        installed="$(install_probe_capture pacman pacman -Qq)" || return
        if printf '%s\n' "$installed" | grep -Fqx rust-analyzer; then workflow_native_run "$context" sudo pacman -R --noconfirm rust-analyzer; fi
      fi
      # Preserve supported full-upgrade semantics only when native packages need installing.
      if workflow_packages_need "$context" pacman;then workflow_native_run "$context" sudo pacman -Syu --noconfirm;fi ;;
  esac
}
workflow_fish_path() {
  if [[ "$(workflow_context_get "$1" platform)" == macos ]]; then printf '%s/bin/fish\n' "$(workflow_context_get "$1" brew_prefix)"
  else command -v fish 2>/dev/null || printf '/usr/bin/fish\n';fi
}
workflow_preflight_shell() {
  local context="$1" user platform
  user="$(workflow_context_get "$context" user)";platform="$(workflow_context_get "$context" platform)"
  [[ -r /etc/shells ]] || { printf 'error: /etc/shells is not readable\n' >&2;return 1; }
  if [[ "$platform" == macos ]]; then dscl . -read "/Users/$user" UserShell >/dev/null
  else getent passwd "$user" >/dev/null;fi
  command -v chsh >/dev/null || { printf 'error: chsh is required for the shell stage\n' >&2;return 1; }
  if ! workflow_will_install "$context" fish; then
    [[ -x "$(workflow_fish_path "$context")" ]] || { printf 'error: install Fish before selecting the shell stage\n' >&2;return 1; }
  fi
  if [[ "$(workflow_context_get "$context" dry_run)" == 0 && "$(workflow_context_get "$context" plan_only)" == 0 ]]; then
    command -v sudo >/dev/null || { printf 'error: the shell stage requires sudo\n' >&2;return 1; }
  fi
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
