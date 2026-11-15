# shellcheck shell=bash
# Adapter inputs: config, mode, config home, session, scratch, plan, directories, system root.
mirror_plan_state() {
  local config="$1" mode="$2" config_home="$3" session="$4" scratch="$5" plan="$6" directories="$7"
  local root rendered owned state_file
  state_file="$config_home/dotfiles/mirror-state.conf"
  root="$(apply_nearest_directory "$config_home")"
  rendered="$scratch/state.conf"
  { printf '# dotfiles mirror state v1\n';printf '%s\n' "$config"; } > "$rendered"
  owned=1
  if [[ -e "$state_file" ]] && ! grep -Fqx '# dotfiles mirror state v1' "$state_file";then owned=0;fi
  mirror_add_file "$rendered" "$state_file" "$root" "$session" "$plan" "$directories" none "$mode" "$owned" || return
}
