# shellcheck shell=bash
install_brew() {
  local record="$1" context="$2" method source_repo brew_cmd package_args=()
  method="$(install_field "$record" method)";source_repo="$(install_field "$record" source_repo)"
  brew_cmd="$(install_context "$context" 3)"
  read -r -a package_args <<< "$(install_field "$record" packages)"
  if [[ -n "$source_repo" ]]; then install_run "$context" "$brew_cmd" tap "$source_repo"; fi
  if [[ "$method" == cask ]]; then
    install_run "$context" "$brew_cmd" install --cask "${package_args[@]}"
  else install_run "$context" "$brew_cmd" install "${package_args[@]}"; fi
}

install_bootstrap() {
  local record="$1" context="$2" method url script code policy
  method="$(install_field "$record" method)"
  if [[ "$method" == xcode ]]; then
    if [[ "$(install_context "$context" 2)" == 1 ]]; then
      install_run "$context" xcode-select --install
      printf 'DRY RUN: complete Command Line Tools installation and rerun before continuing\n'
      return
    fi
    if install_run "$context" xcode-select --install; then :
    else
      code=$?
      case "$code" in 124|130|143) return "$code" ;; esac
      printf 'Command Line Tools installation may already be in progress.\n'
    fi
    printf 'Complete Command Line Tools installation, then rerun this installer.\n'
    return 75
  fi
  url="$(install_field "$record" source_url)"
  if [[ "$(install_context "$context" 2)" == 1 ]]; then
    printf 'DRY RUN: install Homebrew using %s\n' "$url"
  else
    policy="$(install_execution_policy homebrew download)"
    script="$(command_capture "${policy%%|*}" curl -fsSL "$url")"
    install_run "$context" /bin/bash -c "$script"
    [[ -x "$(install_context "$context" 3)" ]] || { printf 'error: Homebrew executable not found after installation\n' >&2; return 1; }
  fi
}
