# shellcheck shell=bash
# Adapter inputs: config, mode, config home, session, scratch, plan, directories, system root.
mirror_plan_environment() {
  local config="$1" mode="$2" config_home="$3" session="$4" scratch="$5" plan="$6" directories="$7"
  local root target rendered kind key variable value owned
  root="$(apply_nearest_directory "$config_home")" || return
  # Persist environment for Fish (the login shell) and an explicit POSIX-shell source file.
  for kind in fish sh;do
    rendered="$scratch/environment.$kind"
    if [[ "$kind" == fish ]];then target="$config_home/fish/conf.d/15-mirrors.fish"
    else target="$config_home/dotfiles/mirrors.sh";fi
    printf '# Managed by dotfiles mirrors\n' > "$rendered"
    while IFS=$'\t' read -r variable key;do
      [[ -n "$variable" && "$variable" != \#* ]] || continue
      value="$(mirror_value "$config" "$key")"
      if [[ "$kind" == fish ]];then printf "set -gx %s '%s'\n" "$variable" "$value" >> "$rendered"
      else printf "export %s='%s'\n" "$variable" "$value" >> "$rendered";fi
    done < "${mirror_library_dir:?}/../mirrors/schema/environment.tsv"
    owned=1
    if [[ -f "$target" ]] && ! grep -Fqx '# Managed by dotfiles mirrors' "$target";then owned=0;fi
    mirror_add_file "$rendered" "$target" "$root" "$session" "$plan" "$directories" none "$mode" "$owned" || return
  done
}
