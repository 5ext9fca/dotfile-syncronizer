# shellcheck shell=bash
# Mirror lifecycle: prepare = process-only installation downloads;
# initialize = fill initially unconfigured settings after installation;
# apply = reconcile currently managed settings to mirrors/current.conf.
mirror_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

mirror_read_config() {
  local file="$1"
  awk '
    BEGIN { n=split("rust_dist rust_update pypi cargo_index npm go_proxy go_sumdb brew_git brew_core brew_cask brew_bottles brew_api ubuntu ubuntu_ports debian debian_security fedora arch manjaro",keys," ");for(i=1;i<=n;i++) allowed[keys[i]]=1 }
    {sub(/\r$/,"");if(/^#/ || /^$/) next;at=index($0,"=");key=substr($0,1,at-1);value=substr($0,at+1)
      if(!at || !(key in allowed) || seen[key]++ || value=="" || value ~ /[|\t \047\042\\]/) {bad=1;next}
      if(key=="go_sumdb") {if(value !~ /^[a-zA-Z0-9.-]+$/) bad=1}
      else if(value !~ /^(https?:\/\/|sparse\+https:\/\/)/) bad=1
      values[key]=value
    }
    END {for(i=1;i<=n;i++) if(!(keys[i] in values)) bad=1;if(bad){print "error: invalid mirror configuration" > "/dev/stderr";exit 1}for(i=1;i<=n;i++)print keys[i] "=" values[keys[i]]}
  ' "$file"
}
mirror_value() { printf '%s\n' "$1" | awk -v key="$2" 'index($0,key "=")==1 {print substr($0,length(key)+2)}'; }

china_mirror_detect_package_manager() {
  if command -v pacman >/dev/null 2>&1;then printf 'pacman\n'
  elif command -v apt-get >/dev/null 2>&1;then printf 'apt\n'
  elif command -v dnf >/dev/null 2>&1;then printf 'dnf\n';fi
}

mirror_prepare_install() {
  local file="${1:-$mirror_library_dir/../mirrors/current.conf}" config
  config="$(mirror_read_config "$file")" || return
  local variable key value
  while IFS=$'\t' read -r variable key;do
    [[ -n "$variable" && "$variable" != \#* ]] || continue
    [[ "$variable" =~ ^[A-Z][A-Z0-9_]*$ ]] || { printf 'error: invalid mirror environment mapping\n' >&2;return 1; }
    value="$(mirror_value "$config" "$key")"
    [[ -n "$value" ]] || { printf 'error: unknown mirror environment key: %s\n' "$key" >&2;return 1; }
    printf -v "$variable" '%s' "$value"
    export "${variable?}"
  done < "$mirror_library_dir/../mirrors/schema/environment.tsv"
  export HOMEBREW_INSTALL_FROM_API=1
}

mirror_skip() {
  local target="$1" root="$2" reason="$3" plan="$4"
  printf 'mirrors|skip||%s||||%s|none|%s|1\n' "$target" "$root" "$reason" >> "$plan"
}

mirror_add_file() {
  local rendered="$1" target="$2" root="$3" session="$4" plan="$5" directories="$6" privilege="$7" mode="$8" owned="${9:-1}" permissions virtual=0 probe
  if apply_virtual "$(dirname -- "$target")" "$directories";then virtual=1;owned=1;mode=apply;fi
  # Mirror-only work must not replace an unrelated application's parent directory.
  # A selected component may already explicitly plan that replacement.
  if [[ "$virtual" == 0 ]];then
    probe="$(dirname -- "$target")"
    while [[ "$probe" != "$root" ]];do
      if [[ -L "$probe" || ( -e "$probe" && ! -d "$probe" ) ]];then mirror_skip "$target" "$root" unmanaged-parent "$plan";return;fi
      [[ "$probe" != / ]] || break
      probe="$(dirname -- "$probe")"
    done
  fi
  if [[ "$virtual" == 0 && ( -L "$target" || ( -e "$target" && ! -f "$target" ) ) ]] || [[ "$owned" == 0 ]];then mirror_skip "$target" "$root" unmanaged "$plan";return;fi
  if [[ "$mode" == initialize && -e "$target" ]];then mirror_skip "$target" "$root" initialized "$plan";return;fi
  if [[ "$virtual" == 0 && -f "$target" ]];then
    if [[ "$(uname -s)" == Darwin ]];then permissions="$(stat -f '%Lp' "$target")";else permissions="$(stat -c '%a' "$target")";fi
  else permissions=644;fi
  chmod "$permissions" "$rendered" || return
  apply_plan_file mirrors copy "$rendered" "$target" "$root" "$session" "$plan" "$directories" "$privilege"
}

# Appends all mirror file operations to the already validated deployment plan.
# The caller owns scratch until execution/printing completes; no target writes occur.
mirror_make_plan() {
  local file="$1" mode="$2" config_home="$3" session="$4" scratch="$5" base_plan="$6" system_root="${7:-/}"
  local config previous_file state_file plan directories
  [[ "$mode" == initialize || "$mode" == apply ]] || { printf 'error: invalid mirror mode\n' >&2;return 1; }
  config="$(mirror_read_config "$file")" || return
  printf '%s\n' "$config" > "$scratch/current.conf"
  mirror_read_config "$mirror_library_dir/../mirrors/legacy.conf" > "$scratch/legacy.conf" || return
  plan="$scratch/mirror-plan";directories="$scratch/directories"
  : > "$plan"
  if [[ -n "$base_plan" ]]; then printf '%s\n' "$base_plan" > "$plan"; fi
  printf '%s\n' "$base_plan" | awk -F '|' '$2=="mkdir" {print $4 "|1"}' > "$directories"
  state_file="$config_home/dotfiles/mirror-state.conf";previous_file="$scratch/previous.conf"
  : > "$previous_file"
  if [[ -f "$state_file" && ! -L "$state_file" ]] && grep -Fqx '# dotfiles mirror state v1' "$state_file";then
    mirror_read_config "$state_file" > "$previous_file" || return
  fi
  local adapter
  for adapter in environment cargo npm go system state;do
    "mirror_plan_$adapter" "$config" "$mode" "$config_home" "$session" "$scratch" "$plan" "$directories" "$system_root" || return
  done
  cat "$plan"
}

# Renderers share only endpoint matching and managed-state loading.
mirror_render() {
  local kind="$1" mode="$2" scratch="$3" input="$4"
  case "$kind" in cargo|npm|go|apt|dnf) ;; *) printf 'error: unknown mirror renderer: %s\n' "$kind" >&2;return 1 ;; esac
  awk -v mode="$mode" -f "$mirror_library_dir/../mirrors/renderers/common.awk" \
    -f "$mirror_library_dir/../mirrors/renderers/$kind.awk" "$scratch/current.conf" "$scratch/previous.conf" "$scratch/legacy.conf" "$input"
}
# shellcheck source=../mirrors/handlers/environment.sh
source "$mirror_library_dir/../mirrors/handlers/environment.sh"
# shellcheck source=../mirrors/handlers/cargo.sh
source "$mirror_library_dir/../mirrors/handlers/cargo.sh"
# shellcheck source=../mirrors/handlers/npm.sh
source "$mirror_library_dir/../mirrors/handlers/npm.sh"
# shellcheck source=../mirrors/handlers/go.sh
source "$mirror_library_dir/../mirrors/handlers/go.sh"
# shellcheck source=../mirrors/handlers/system.sh
source "$mirror_library_dir/../mirrors/handlers/system.sh"
# shellcheck source=../mirrors/handlers/state.sh
source "$mirror_library_dir/../mirrors/handlers/state.sh"
