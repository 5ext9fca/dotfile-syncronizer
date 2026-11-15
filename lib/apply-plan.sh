# shellcheck shell=bash
# shellcheck disable=SC2154
apply_virtual() {
  local path="$1" directories="$2" known virtual
  while IFS='|' read -r known virtual; do
    if [[ "$virtual" == 1 && ( "$path" == "$known" || "$path" == "$known/"* ) ]];then return 0;fi
  done < "$directories"
  return 1
}

apply_plan_directory() {
  local component="$1" path="$2" root="$3" session="$4" plan="$5" directories="$6" privilege="$7"
  local parent before backup='' virtual=0
  [[ "$path" != "$root" ]] || return 0
  if awk -F '|' -v target="$path" '$1==target {found=1} END {exit !found}' "$directories";then return 0;fi
  parent="$(dirname -- "$path")"
  apply_plan_directory "$component" "$parent" "$root" "$session" "$plan" "$directories" "$privilege" || return
  if ! apply_virtual "$parent" "$directories" && [[ -d "$path" && ! -L "$path" ]];then
    printf '%s|0\n' "$path" >> "$directories"
    return
  fi
  if apply_virtual "$parent" "$directories";then before=absent
  else before="$(apply_state "$path")" || return;fi
  if [[ "$before" == absent ]];then virtual=1
  elif [[ -d "$path" && ! -L "$path" ]];then
    printf '%s|0\n' "$path" >> "$directories"
    return
  else
    virtual=1;backup="$session/files/$component/${path#/}"
  fi
  printf '%s|mkdir||%s|%s|%s||%s|%s|directory|1\n' "$component" "$path" "$backup" "$before" "$root" "$privilege" >> "$plan"
  printf '%s|%s\n' "$path" "$virtual" >> "$directories"
}

# Plan columns: component|action|source|target|backup|before|source_state|root|privilege|reason
apply_plan_file() {
  local component="$1" method="$2" source="$3" target="$4" root="$5" session="$6" plan="$7" directories="$8" privilege="$9"
  local before source_state parent backup='' action="$method" reason=new nearest source_device target_device
  parent="$(dirname -- "$target")"
  apply_plan_directory "$component" "$parent" "$root" "$session" "$plan" "$directories" "$privilege" || return
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'error: unreadable or unsupported source: %s\n' "$source" >&2;return 1; }
  source_state="$(apply_state "$source")" || return
  if apply_virtual "$parent" "$directories";then before=absent
  else before="$(apply_state "$target")" || return;fi
  nearest="$parent"
  while apply_virtual "$nearest" "$directories" || [[ ! -d "$nearest" || -L "$nearest" ]];do nearest="$(dirname -- "$nearest")";done
  if [[ "$privilege" != sudo && ( ! -w "$nearest" || ! -x "$nearest" ) ]];then printf 'error: target parent is not writable: %s\n' "$nearest" >&2;return 1;fi
  if [[ "$method" == hardlink ]];then
    source_device="$(apply_stat "$source")";target_device="$(apply_stat "$nearest")"
    [[ "${source_device%%:*}" == "${target_device%%:*}" ]] || { printf 'error: hard link crosses filesystems: %s -> %s\n' "$source" "$target" >&2;return 1; }
  fi
  if [[ "$before" != absent ]];then
    reason=replace;backup="$session/files/$component/${target#/}"
    if [[ ! -L "$target" && -f "$target" ]];then
      if [[ "$method" == hardlink && "$source" -ef "$target" ]] || { [[ "$method" == copy ]] && cmp -s "$source" "$target"; };then
        action=skip;reason=unchanged;backup=''
      fi
    fi
  fi
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|1\n' "$component" "$action" "$source" "$target" "$backup" "$before" "$source_state" "$root" "$privilege" "$reason" >> "$plan"
}

apply_excluded() {
  local relative="$1" exclusions="$2" exclusion values=()
  IFS=';' read -r -a values <<< "$exclusions"
  for exclusion in ${values[@]+"${values[@]}"};do
    [[ "$relative" == "$exclusion" || "$relative" == "$exclusion/"* ]] && return 0
  done
  return 1
}

apply_read_items() {
  local directory="$1" platform="$2" file output
  for file in "$directory"/*.conf;do [[ -s "$file" ]] || { printf 'error: missing or empty apply item: %s\n' "$file" >&2;return 1; };done
  output="$(LC_ALL=C awk -v platform="$platform" -f "$apply_library_dir/apply-items.awk" "$apply_library_dir/../apply/schema/fields.tsv" "$directory"/*.conf)" || return
  printf '%s\n' "$output" | LC_ALL=C sort
}

apply_make_plan() (
  local roots="${8:-}" root_value
  local render_scratch="${6:-}" preview="${7:-0}" condition renderer
  local repo="$1" items="$2" config="$3" session="$4" selection="$5" scratch definitions component source _target_root target method exclusions source_path target_path root entries entry relative other directories plan
  scratch="$(mktemp -d)" || return
  trap 'rm -rf "$scratch"' EXIT
  plan="$scratch/plan";directories="$scratch/directories"
  : > "$plan";: > "$directories";: > "$scratch/targets"
  definitions="$(apply_read_items "$items" unix)" || return
  [[ "$selection" != none ]] || return 0
  if [[ -z "$roots" ]];then roots="$(printf 'config_home|%s\nhome|%s\n' "$config" "${HOME:-}")";fi
  if [[ -n "$selection" ]];then
    while IFS= read -r component;do
      [[ -n "$component" ]] || continue
      printf '%s\n' "$definitions" | awk -F '|' -v id="$component" '$1==id {found=1} END {exit !found}' || { printf 'error: unknown component: %s\n' "$component" >&2;return 1; }
    done <<< "$selection"
  fi
  while IFS='|' read -r component source _target_root target method exclusions condition renderer;do
    [[ -n "$component" ]] || continue
    if [[ -n "$selection" ]] && ! printf '%s\n' "$selection" | grep -Fxq "$component";then continue;fi
    root_value="$(printf '%s\n' "$roots" | awk -F '|' -v key="$_target_root" '$1==key {print substr($0,length(key)+2)}')"
    [[ "$root_value" == /* ]] || { printf 'error: missing or non-absolute target root: %s\n' "$_target_root" >&2;return 1; }
    config="$(apply_resolve_root "$root_value")" || return
    if [[ "$condition" == linux-kde ]] && ! desktop_fonts_supported;then
      printf '%s|skip||%s||||%s|none|requires-native-linux-kde|1\n' "$component" "$config/$target" "$config" >> "$plan"
      continue
    fi
    source_path="$repo/$source";target_path="$config/$target"
    apply_safe_path "$source_path" && apply_safe_path "$target_path" || return
    [[ "$target_path" != "$repo" && "$target_path" != "$repo/"* && "$repo" != "$target_path/"* ]] || { printf 'error: source and destination overlap\n' >&2;return 1; }
    [[ "$session" != "$target_path" && "$session" != "$target_path/"* && "$target_path" != "$session/"* ]] || { printf 'error: backup and destination overlap\n' >&2;return 1; }
    while IFS= read -r other;do
      [[ "$target_path" != "$other" && "$target_path" != "$other/"* && "$other" != "$target_path/"* ]] || { printf 'error: overlapping component destinations\n' >&2;return 1; }
    done < "$scratch/targets"
    printf '%s\n' "$target_path" >> "$scratch/targets"
    # Reject symlinks anywhere inside a declared repository source path.
    other="$source_path"
    while [[ "$other" != "$repo" ]];do
      [[ ! -L "$other" ]] || { printf 'error: source symlink: %s\n' "$other" >&2;return 1; }
      other="$(dirname -- "$other")"
    done
    root="$(apply_nearest_directory "$config")" || return
    if [[ -d "$source_path" ]];then
      entries="$(apply_list "$source_path")" || return
      apply_plan_directory "$component" "$target_path" "$root" "$session" "$plan" "$directories" none || return
      while IFS= read -r entry;do
        [[ -n "$entry" ]] || continue
        relative="${entry#"$source_path/"}"
        if apply_excluded "$relative" "$exclusions";then
          printf '%s|skip|%s|%s|||%s|%s|none|excluded|1\n' "$component" "$entry" "$target_path/$relative" '' "$root" >> "$plan"
          continue
        fi
        if [[ -L "$entry" ]];then printf 'error: source symlink: %s\n' "$entry" >&2;return 1
        elif [[ -d "$entry" ]];then apply_plan_directory "$component" "$target_path/$relative" "$root" "$session" "$plan" "$directories" none || return
        elif [[ -f "$entry" ]];then apply_plan_file "$component" "$method" "$entry" "$target_path/$relative" "$root" "$session" "$plan" "$directories" none || return
        else printf 'error: unsupported source: %s\n' "$entry" >&2;return 1;fi
      done <<< "$entries"
    elif [[ -f "$source_path" ]];then
      [[ -z "$exclusions" ]] || { printf 'error: file components cannot use exclusions\n' >&2;return 1; }
      apply_plan_file "$component" "$method" "$source_path" "$target_path" "$root" "$session" "$plan" "$directories" none || return
    else printf 'error: missing source: %s\n' "$source_path" >&2;return 1;fi
    if [[ "$renderer" == desktop-fonts ]];then
      [[ -n "$render_scratch" ]] || { printf 'error: desktop-fonts requires caller-owned scratch\n' >&2;return 1; }
      desktop_fonts_plan "$component" "$config" "$session" "$render_scratch" "$plan" "$directories" "$preview" "$source_path" || return
    fi
  done <<< "$definitions"
  cat "$plan"
)
