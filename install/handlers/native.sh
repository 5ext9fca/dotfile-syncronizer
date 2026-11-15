# shellcheck shell=bash
# Native package managers. record and context are the complete handler interface.
install_native() {
  local record="$1" context="$2" method packages source_repo source_release package
  local package_args=()
  method="$(install_field "$record" method)";packages="$(install_field "$record" packages)"
  source_repo="$(install_field "$record" source_repo)";source_release="$(install_field "$record" source_release)"
  read -r -a package_args <<< "$packages"
  case "$method" in
    apt)
      if [[ -n "$source_release" ]]; then
        install_run "$context" sudo apt-get install -y -t "$source_release" "${package_args[@]}"
      else install_run "$context" sudo apt-get install -y "${package_args[@]}"; fi ;;
    dnf)
      if [[ -n "$source_repo" ]]; then
        install_run "$context" sudo dnf --enablerepo="$source_repo" install -y "${package_args[@]}"
      else install_run "$context" sudo dnf install -y "${package_args[@]}"; fi ;;
    pacman)
      if [[ -n "$source_repo" ]]; then
        for ((package=0;package<${#package_args[@]};package++)); do package_args[package]="$source_repo/${package_args[package]}"; done
      fi
      install_run "$context" sudo pacman -S --needed --noconfirm "${package_args[@]}" ;;
  esac
}

install_probe_apt_or_snap() {
  local record="$1" context="${2:-}" candidate fallback output code candidate_record candidates=()
  read -r -a candidates <<< "$(install_field "$record" packages)"
  for candidate in "${candidates[@]}"; do
    candidate_record="$(install_record_update "$record" method apt packages "$candidate")" || return
    output="$(install_resume_package_state "$candidate_record" "$context")" || return
    if [[ "$output" == present ]];then printf 'present\n';return;fi
  done
  fallback="$(install_field "$record" fallback)"
  if command -v snap >/dev/null 2>&1; then
    if install_probe_capture apt-or-snap snap list "$fallback" >/dev/null 2>&1;then printf 'present\n';return
    else code=$?;[[ "$code" == 1 ]] || return "$code";fi
  fi
  for candidate in "${candidates[@]}"; do
    output="$(LC_ALL=C install_probe_capture apt-or-snap apt-cache policy "$candidate")" || return
    if printf '%s\n' "$output" | awk '$1=="Candidate:" && $2!="(none)" {found=1} END {exit !found}'; then
      printf 'apt:%s\n' "$candidate";return
    fi
  done
  printf 'snap:%s\n' "$fallback"
}

install_apt_or_snap() {
  local record="$1" context="$2" state
  state="$(install_field "$record" state)"
  case "$state" in
    apt:*) install_run "$context" sudo apt-get install -y "${state#apt:}" ;;
    snap:*) install_run "$context" sudo snap install "${state#snap:}" --classic ;;
    *) printf 'error: apt-or-snap requires an inspected plan\n' >&2; return 1 ;;
  esac
}
