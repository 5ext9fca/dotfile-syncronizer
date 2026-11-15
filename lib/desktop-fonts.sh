# shellcheck shell=bash
desktop_fonts_supported() {
  [[ "$(uname -s)" == Linux && -z "${WSL_INTEROP:-}${WSL_DISTRO_NAME:-}" ]] || return 1
  ! grep -qi microsoft /proc/sys/kernel/osrelease || return 1
  case ":${XDG_CURRENT_DESKTOP:-}:" in *:KDE:*) return 0 ;; *) return 1 ;; esac
}

desktop_fonts_plan() {
  local preview="${7:-0}"
  local component="$1" config="$2" session="$3" scratch="$4" plan="$5" directories="$6"
  local family available missing=0 relative target candidate before after root permissions parent
  command -v python3 >/dev/null || { printf 'error: desktop-fonts requires python3\n' >&2;return 1; }
  if command -v fc-list >/dev/null;then available="$(command_capture 30 fc-list --format '%{family}\n')" || return
  else available='';fi
  for family in 'PingFang SC' 'JetBrainsMono Nerd Font' 'Noto Sans CJK SC';do
    if ! printf '%s\n' "$available" | awk -F ',' -v family="$family" '{for(i=1;i<=NF;i++) if($i==family) found=1} END {exit !found}';then
      printf 'desktop-fonts: missing %s; run ./install/linux.sh --yes before deployment\n' "$family" >&2
      missing=1
    fi
  done
  if [[ "$missing" == 1 && "$preview" != 1 ]];then return 1;fi
  root="$(apply_nearest_directory "$config")" || return
  for relative in kdeglobals gtk-3.0/settings.ini gtk-4.0/settings.ini;do
    target="$config/$relative";candidate="$scratch/desktop-${relative//\//-}"
    apply_safe_path "$target" || return
    [[ "$target" != "$session" && "$target" != "$session/"* && "$session" != "$target/"* ]] || { printf 'error: desktop font target overlaps backups\n' >&2;return 1; }
    parent="$target"
    while [[ "$parent" != "$root" ]];do
      [[ ! -L "$parent" ]] || { printf 'error: desktop font path is a symlink: %s\n' "$parent" >&2;return 1; }
      parent="$(dirname -- "$parent")"
    done
    [[ ! -e "$target" || -f "$target" ]] || { printf 'error: desktop font target is not a file\n' >&2;return 1; }
    before="$(apply_state "$target")" || return
    command_run probe 0 30 '' -- python3 "$apply_library_dir/../apply/renderers/desktop-fonts.py" "$relative" "$target" "$candidate" || return
    after="$(apply_state "$target")" || return
    [[ "$before" == "$after" ]] || { printf 'error: desktop settings changed during rendering: %s\n' "$target" >&2;return 1; }
    permissions=644
    [[ ! -f "$target" ]] || permissions="$(stat -c '%a' "$target")"
    chmod "$permissions" "$candidate" || return
    apply_plan_file "$component" copy "$candidate" "$target" "$root" "$session" "$plan" "$directories" none || return
  done
}
