# shellcheck shell=bash
install_repository() {
  local record="$1" context="$2" method id url source_repo key_url keyring repository_file entry backup_root package_args=()
  method="$(install_field "$record" method)";id="$(install_field "$record" id)"
  read -r -a package_args <<< "$(install_field "$record" packages)"
  if [[ "$method" == dnf-copr ]]; then
    source_repo="$(install_field "$record" source_repo)"
    install_run "$context" sudo dnf -y copr enable "$source_repo"
    install_run "$context" sudo dnf install -y "${package_args[@]}"
    return
  fi
  url="$(install_field "$record" source_url)";key_url="$(install_field "$record" key_url)"
  keyring="/usr/share/keyrings/$(install_field "$record" keyring)"
  repository_file="/etc/apt/sources.list.d/$id.list"
  backup_root="$(install_context "$context" 5)"
  entry="deb [signed-by=$keyring] $url * *"
  if [[ ! -r "$keyring" ]]; then install_run "$context" sudo curl -fsSL -o "$keyring" "$key_url"; fi
  if [[ ! -r "$repository_file" ]] || ! grep -Fqx "$entry" "$repository_file"; then
    if [[ -e "$repository_file" ]]; then
      install_run "$context" sudo mkdir -p "$backup_root/system/apt"
      install_run "$context" sudo cp -p "$repository_file" "$backup_root/system/apt/$id.list"
    fi
    if [[ "$(install_context "$context" 2)" == 1 ]]; then
      printf 'DRY RUN: write %q to %q with sudo\n' "$entry" "$repository_file"
    else printf '%s\n' "$entry" | sudo tee "$repository_file" >/dev/null; fi
  fi
  install_run "$context" sudo apt-get update
  install_run "$context" sudo apt-get install -y "${package_args[@]}"
}
