# shellcheck shell=bash
# Adapter inputs: config, mode, config home, session, scratch, plan, directories, system root.
mirror_plan_go() {
  local mode="$2" session="$4" scratch="$5" plan="$6" directories="$7"
  local root target rendered input
  if command -v go >/dev/null 2>&1;then
    target="$(go env GOENV)" || return
    if [[ "$target" != off && "$target" == /* ]];then
      root="$(apply_nearest_directory "$(dirname -- "$target")")";rendered="$scratch/go.env";input=/dev/null
      [[ ! -f "$target" ]] || input="$target"
      mirror_render go "$mode" "$scratch" "$input" > "$rendered" || return
      mirror_add_file "$rendered" "$target" "$root" "$session" "$plan" "$directories" none apply || return
    fi
  fi
}
