# shellcheck shell=bash
# Adapter inputs: config, mode, config home, session, scratch, plan, directories, system root.
mirror_plan_npm() {
  local config="$1" mode="$2" session="$4" scratch="$5" plan="$6" directories="$7"
  local root target rendered owned input old expected
  local previous_file="$scratch/previous.conf"
  target="${NPM_CONFIG_USERCONFIG:-$HOME/.npmrc}"
  target="$(apply_resolve_root "$(dirname -- "$target")")/$(basename -- "$target")" || return
  root="$(apply_nearest_directory "$(dirname -- "$target")")" || return
  rendered="$scratch/npmrc";owned=1;input=/dev/null
  if [[ -f "$target" ]];then
    input="$target"
    if grep -Eq '^[[:space:]]*registry[[:space:]]*=' "$target";then
      old="$(awk -F= '$1 ~ /^[ \t]*registry[ \t]*$/ {sub(/^[ \t]+/,"",$2);sub(/[ \t]+$/,"",$2);print $2;exit}' "$target")"
      expected="$(mirror_value "$(cat "$previous_file")" npm)"
      if [[ "$mode" == initialize || ( "$old" != "$(mirror_value "$(cat "$scratch/legacy.conf")" npm)" && "$old" != "$expected" && "$old" != "$(mirror_value "$config" npm)" ) ]];then owned=0;fi
    fi
  elif apply_exists "$target";then owned=0;fi
  mirror_render npm "$mode" "$scratch" "$input" > "$rendered" || return
  # Existing npmrc without a registry is initially unconfigured; append just that key.
  mirror_add_file "$rendered" "$target" "$root" "$session" "$plan" "$directories" none apply "$owned" || return
}
