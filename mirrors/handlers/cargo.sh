# shellcheck shell=bash
# Adapter inputs: config, mode, config home, session, scratch, plan, directories, system root.
mirror_plan_cargo() {
  local config="$1" mode="$2" session="$4" scratch="$5" plan="$6" directories="$7"
  local root target rendered value owned
  target="$(apply_resolve_root "${CARGO_HOME:-$HOME/.cargo}")/config.toml" || return
  root="$(apply_nearest_directory "$(dirname -- "$target")")" || return
  rendered="$scratch/cargo.toml";owned=1
  if [[ -e "$target" ]];then
    if [[ ! -f "$target" ]] || ! grep -Fqx '[source.rsproxy-sparse]' "$target" || ! grep -Eq '^replace-with[[:space:]]*=[[:space:]]*"rsproxy-sparse"' "$target";then owned=0;: > "$rendered"
    else mirror_render cargo "$mode" "$scratch" "$target" > "$rendered" || return;fi
  else
    value="$(mirror_value "$config" cargo_index)"
    printf '# Managed by dotfiles mirrors\n[source.crates-io]\nreplace-with = "rsproxy-sparse"\n\n[source.rsproxy-sparse]\nregistry = "%s"\n\n[registries.rsproxy]\nindex = "%s"\n\n[net]\ngit-fetch-with-cli = true\n' "$value" "$value" > "$rendered"
  fi
  mirror_add_file "$rendered" "$target" "$root" "$session" "$plan" "$directories" none "$mode" "$owned" || return
}
