# shellcheck shell=bash
install_cargo() {
  local record="$1" context="$2" source_url target_dir registry_name=dotfiles-install package_args=()
  source_url="$(install_field "$record" source_url)"
  target_dir="${CARGO_TARGET_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/cargo-install}"
  read -r -a package_args <<< "$(install_field "$record" packages)"
  if [[ -z "$source_url" ]]; then
    install_run "$context" env CARGO_TARGET_DIR="$target_dir" cargo install --locked "${package_args[@]}"
  elif [[ "$source_url" == https://github.com/rust-lang/crates.io-index || "$source_url" == sparse+https://index.crates.io/ ]]; then
    # Explicit registry selection also works when the user has configured a mirror.
    install_run "$context" env CARGO_TARGET_DIR="$target_dir" cargo install --locked --index "$source_url" "${package_args[@]}"
  else
    # Match the existing shared mirror name to avoid duplicate registry sources.
    if [[ "$source_url" == sparse+https://rsproxy.cn/index/ ]]; then registry_name=rsproxy-sparse; fi
    install_run "$context" env CARGO_TARGET_DIR="$target_dir" cargo \
      --config "source.crates-io.replace-with=\"$registry_name\"" \
      --config "source.$registry_name.registry=\"$source_url\"" install --locked "${package_args[@]}"
  fi
}

install_pipx() {
  local record="$1" context="$2" source_url action package
  source_url="$(install_field "$record" source_url)";action="$(install_field "$record" action)"
  package="$(install_field "$record" packages)"
  if [[ -n "$source_url" ]]; then
    install_run "$context" env PIP_INDEX_URL="$source_url" pipx "$action" "$package"
  else install_run "$context" pipx "$action" "$package"; fi
}

install_rustup() {
  local record="$1" context="$2" source_url toolchain components platform command=rustup prefix
  local env_args=()
  source_url="$(install_field "$record" source_url)";toolchain="$(install_field "$record" packages)"
  components="$(install_field "$record" components)";platform="$(install_context "$context" 1)"
  if [[ -n "$source_url" ]]; then env_args+=("RUSTUP_DIST_SERVER=$source_url"); fi
  case "$platform" in
    linux.apt) command=/usr/bin/rustup ;;
    macos) prefix="$(install_context "$context" 4)";command="$prefix/opt/rustup/bin/rustup" ;;
    linux.dnf)
      if [[ -x "$HOME/.cargo/bin/rustup" ]]; then command="$HOME/.cargo/bin/rustup"
      else
        install_run "$context" env ${env_args[@]+"${env_args[@]}"} /usr/bin/rustup-init -y --no-modify-path \
          --profile minimal --default-toolchain "$toolchain" --component "$components"
        return
      fi ;;
  esac
  install_run "$context" env ${env_args[@]+"${env_args[@]}"} "$command" toolchain install "$toolchain" --profile minimal --component "$components"
  install_run "$context" env ${env_args[@]+"${env_args[@]}"} "$command" default "$toolchain"
}
