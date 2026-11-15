# shellcheck shell=bash
install_script() {
  local record="$1" context="$2" url shell environment script_args=() env_args=()
  url="$(install_field "$record" source_url)";shell="$(install_field "$record" shell)"
  environment="$(install_field "$record" env)"
  read -r -a script_args <<< "$(install_field "$record" args)"
  if [[ -n "$environment" ]]; then env_args+=("$environment"); fi
  if [[ "$(install_context "$context" 2)" == 1 ]]; then
    printf 'DRY RUN: curl -fsSL %q | env' "$url"
    printf ' %q' ${env_args[@]+"${env_args[@]}"} "$shell" -s -- ${script_args[@]+"${script_args[@]}"}
    printf '\n'
  else
    install_run "$context" install_script_pipeline "$url" "$environment" "$shell" ${script_args[@]+"${script_args[@]}"}
  fi
}

# Run the entire pipeline in the command worker so cancellation owns both sides.
install_script_pipeline() {
  local url="$1" environment="$2" shell="$3" env_args=()
  shift 3
  if [[ -n "$environment" ]];then env_args+=("$environment");fi
  curl -fsSL "$url" | env ${env_args[@]+"${env_args[@]}"} "$shell" -s -- "$@"
}

install_font_download() {
  local record="$1" context="$2" id url files expected_family
  id="$(install_field "$record" id)";url="$(install_field "$record" source_url)"
  files="$(install_field "$record" font_files)"
  expected_family="$(install_field "$record" font_family)"
  printf 'Font destination: %s/.local/share/fonts/%s/\n' "$HOME" "$id"
  install_run "$context" install_font_download_files "$id" "$url" "$files" "$expected_family"
}

# Download and parse the entire set before publishing any font. No remote code.
# This worker runs under the existing command timeout/cancellation policy.
install_font_download_files() (
  set -euo pipefail
  local id="$1" url="$2" files="$3" expected_family="$4" scratch target file family
  [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ && "$url" == https://* && -n "$files" ]] || return 2
  [[ "$expected_family" =~ ^[A-Za-z0-9][A-Za-z0-9\ ._-]*$ ]] || return 2
  target="$HOME/.local/share/fonts/$id"
  scratch="$(mktemp -d)" || return
  trap 'rm -rf -- "$scratch"' EXIT
  for file in $files;do
    [[ "$file" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*\.(otf|ttf)$ ]] || { printf 'error: unsafe font filename: %s\n' "$file" >&2;return 2; }
    curl -fLSs --connect-timeout 15 --max-time 120 "${url%/}/$file" -o "$scratch/$file" || { printf 'error: font download failed: %s\n' "$file" >&2;return 1; }
    family="$(fc-scan --format '%{family}' "$scratch/$file")" || { printf 'error: font parsing failed: %s\n' "$file" >&2;return 1; }
    [[ -n "$family" ]] || { printf 'error: invalid font data: %s\n' "$file" >&2;return 1; }
    if [[ ",$family," != *",$expected_family,"* ]];then
      printf 'error: expected %s in %s, received %s\n' "$expected_family" "$file" "$family" >&2;return 1
    fi
  done
  [[ ! -L "$target" ]] || { printf 'error: font destination is a symlink: %s\n' "$target" >&2;return 1; }
  mkdir -p "$target" || return
  for file in $files;do
    [[ ! -L "$target/$file" ]] || { printf 'error: font target is a symlink: %s\n' "$target/$file" >&2;return 1; }
    [[ ! -e "$target/$file" || -f "$target/$file" ]] || return 1
    install -m 644 "$scratch/$file" "$target/$file" || return
  done
  fc-cache -f "$target"
)
