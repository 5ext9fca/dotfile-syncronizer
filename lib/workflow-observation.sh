# shellcheck shell=bash
# Read-only observations. Stage selection and prerequisites belong to Python.
workflow_native_query() {
  local query="$1" first="${2:-}" second="${3:-}"
  case "$query" in
    command-present) if command -v "$first" >/dev/null 2>&1;then printf 1;else printf 0;fi ;;
    executable) if [[ -x "$first" ]];then printf 1;else printf 0;fi ;;
    pacman-packages) install_probe_capture pacman pacman -Qq ;;
    package-manager)
      if command -v pacman >/dev/null 2>&1;then printf pacman
      elif command -v apt-get >/dev/null 2>&1;then printf apt
      elif command -v dnf >/dev/null 2>&1;then printf dnf;fi ;;
    shell-account)
      if [[ "$first" == macos ]];then dscl . -read "/Users/$second" UserShell >/dev/null
      else getent passwd "$second" >/dev/null;fi ;;
    fish-path)
      if [[ "$first" == macos ]];then printf '%s/bin/fish' "$second"
      else command -v fish 2>/dev/null || printf /usr/bin/fish;fi ;;
    *) printf 'error: unsupported native workflow query: %s\n' "$query" >&2;return 65 ;;
  esac
}
