# shellcheck shell=bash
# Adapter inputs: config, mode, config home, session, scratch, plan, directories, system root.
mirror_plan_system() {
  local config="$1" mode="$2" session="$4" scratch="$5" plan="$6" directories="$7" system_root="$8"
  local manager privilege source kind rendered key branch value legacy old root
  local previous_file="$scratch/previous.conf"
  manager="$(china_mirror_detect_package_manager)";privilege=sudo
  [[ "$system_root" == / ]] || privilege=none
  for source in "$system_root"/etc/apt/sources.list "$system_root"/etc/apt/sources.list.d/*.list "$system_root"/etc/apt/sources.list.d/*.sources "$system_root"/etc/yum.repos.d/fedora.repo "$system_root"/etc/yum.repos.d/fedora-updates.repo "$system_root"/etc/pacman.d/mirrorlist;do
    [[ -f "$source" && -r "$source" && ! -L "$source" ]] || continue
    source="${source/#\/\//\/}"
    case "$source" in
      */apt/*) [[ "$manager" == apt ]] || continue;kind=apt ;;
      */yum.repos.d/*) [[ "$manager" == dnf ]] || continue;kind=dnf ;;
      */pacman.d/*) [[ "$manager" == pacman ]] || continue;kind=pacman ;;
    esac
    rendered="$(mktemp "$scratch/system.XXXXXX")" || return
    if [[ "$kind" == pacman ]];then
      key=arch;branch=''
      if command -v pacman-mirrors >/dev/null 2>&1;then
        key=manjaro;branch="/$(pacman-mirrors --get-branch)" || return
        [[ "$branch" =~ ^/[a-zA-Z0-9-]+$ ]] || return 1
      fi
      value="$(mirror_value "$config" "$key")$branch"
      legacy="$(mirror_value "$(cat "$scratch/legacy.conf")" "$key")$branch"
      old="$(mirror_value "$(cat "$previous_file")" "$key")$branch"
      if [[ "$mode" == initialize ]] && { grep -Fq "$legacy" "$source" || grep -Fq "$value" "$source"; };then cp "$source" "$rendered"
      else
        # Pacman expands these placeholders, not the shell.
        # shellcheck disable=SC2016
        printf 'Server = %s/$repo/%s$arch\n' "$value" "$([[ "$key" == arch ]] && printf os/)" > "$rendered"
        awk -v old="$old" -v legacy="$legacy" -v current="$value" 'index($0,"Server = " old "/")!=1 && index($0,"Server = " legacy "/")!=1 && index($0,"Server = " current "/")!=1 {print}' "$source" >> "$rendered"
      fi
    else mirror_render "$kind" "$mode" "$scratch" "$source" > "$rendered" || return;fi
    root="$(apply_nearest_directory "$system_root")" || return
    mirror_add_file "$rendered" "$source" "$root" "$session" "$plan" "$directories" "$privilege" apply || return
  done
}
