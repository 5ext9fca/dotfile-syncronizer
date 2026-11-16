# shellcheck shell=bash
# Scheduling and report content belong to Python; handlers retain native execution.
install_items_execute() {
  dotfiles_python_init || return
  dotfiles_request install-execute-native style unix native_shell "$BASH" items "$1" native_context "$2" results "${3:-}" resume "${4:-0}" dry "$(install_context "$2" 2)" policy_path "${install_policy_file_override:-$install_policy_library_dir/../install/schema/execution.tsv}"
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

