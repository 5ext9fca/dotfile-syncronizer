# shellcheck shell=bash
# Repository selection uses host facts supplied by the Linux entry point.
install_docker_target() {
  local context="$1" distro codename
  distro="$(install_context "$context" 7)";codename="$(install_context "$context" 8)"
  case "${context%%|*}:$distro" in
    linux.dnf:fedora|linux.dnf:centos|linux.dnf:rhel) ;;
    linux.apt:debian|linux.apt:ubuntu)
      [[ "$codename" =~ ^[a-z][a-z0-9-]*$ ]] || {
        printf 'error: Docker CE requires a valid Debian/Ubuntu release codename\n' >&2;return 1;
      } ;;
    *) printf 'error: Docker CE repository is not configured for %s (%s); use a supported distribution or adjust the Docker declaration\n' "$distro" "${context%%|*}" >&2;return 1 ;;
  esac
  printf '%s\n' "$distro"
}

install_docker_download() {
  local context="$1" target="$2" url="$3" policy
  policy="$(install_execution_policy docker-ce download)" || return
  command_run mutation "$(install_context "$context" 2)" "${policy%%|*}" '' -- curl -fsSL -o "$target" "$url"
}

install_docker_publish() {
  local context="$1" source="$2" target="$3" backup
  if [[ "$(install_context "$context" 2)" != 1 ]] && cmp -s "$source" "$target";then return;fi
  if [[ -e "$target" || -L "$target" ]];then
    backup="$(install_context "$context" 5)/system/docker${target}"
    install_run "$context" sudo mkdir -p "${backup%/*}"
    install_run "$context" sudo cp -p "$target" "$backup"
  fi
  install_run "$context" sudo install -m 0644 "$source" "$target"
}

install_docker_ce() (
  # Private staging is removed on ordinary exit; no installation verification.
  set -e
  local record="$1" context="$2" distro url codename staging entry packages=()
  distro="$(install_docker_target "$context")"
  url="$(install_field "$record" source_url)/$distro"
  codename="$(install_context "$context" 8)"
  read -r -a packages <<< "$(install_field "$record" packages)"
  if [[ "$(install_context "$context" 2)" == 1 ]];then staging=/tmp/dotfiles-docker-preview
  else staging="$(mktemp -d)";trap 'rm -rf -- "$staging"' EXIT;fi
  case "${context%%|*}" in
    linux.dnf)
      install_docker_download "$context" "$staging/docker-ce.repo" "$url/docker-ce.repo"
      install_docker_publish "$context" "$staging/docker-ce.repo" /etc/yum.repos.d/docker-ce.repo
      install_run "$context" sudo dnf --enablerepo=docker-ce-stable install -y "${packages[@]}" ;;
    linux.apt)
      install_run "$context" sudo install -m 0755 -d /etc/apt/keyrings
      install_docker_download "$context" "$staging/docker.asc" "$url/gpg"
      install_docker_publish "$context" "$staging/docker.asc" /etc/apt/keyrings/docker.asc
      entry="deb [signed-by=/etc/apt/keyrings/docker.asc] $url $codename stable"
      if [[ "$(install_context "$context" 2)" == 1 ]];then printf 'DRY RUN: stage Docker repository: %s\n' "$entry"
      else printf '%s\n' "$entry" > "$staging/docker.list";fi
      install_docker_publish "$context" "$staging/docker.list" /etc/apt/sources.list.d/docker.list
      install_run "$context" sudo apt-get update
      install_run "$context" sudo apt-get install -y "${packages[@]}" ;;
  esac
)
