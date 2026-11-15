# shellcheck shell=bash
# Pure filesystem inspection; no mutations. Paths in records exclude |, CR, LF, TAB.
apply_safe_path() {
  case "$1" in *'|'*|*$'\n'*|*$'\r'*|*$'\t'*) printf 'error: unsupported control character or pipe in path: %q\n' "$1" >&2; return 1 ;; esac
}

apply_stat() {
  if [[ "$(uname -s)" == Darwin ]]; then stat -f '%d:%i' "$1"; else stat -c '%d:%i' "$1"; fi
}

apply_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d ' ' -f1; else shasum -a 256 | cut -d ' ' -f1; fi
}

apply_exists() { [[ -e "$1" || -L "$1" ]]; }

apply_list() {
  local directory="$1" scratch entry output=''
  scratch="$(mktemp)" || return
  if ! find "$directory" -mindepth 1 -print0 > "$scratch"; then rm -f "$scratch";return 1;fi
  # Removing the scratch file on validation failure is intentional.
  # shellcheck disable=SC2094
  while IFS= read -r -d '' entry; do
    if ! apply_safe_path "$entry"; then rm -f "$scratch";return 1;fi
    output="${output}${entry}"$'\n'
  done < "$scratch"
  rm -f "$scratch"
  if [[ -n "$output" ]]; then printf '%s' "$output" | LC_ALL=C sort;fi
}

# Content signature intentionally ignores inode numbers for cross-volume copies.
apply_content() {
  local path="$1" entries entry relative
  if [[ -L "$path" ]]; then printf 'l:%s\n' "$(readlink "$path" | apply_hash)"
  elif [[ -f "$path" ]]; then printf 'f:%s\n' "$(apply_hash < "$path")"
  elif [[ -d "$path" ]]; then
    entries="$(apply_list "$path")" || return
    {
      while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        relative="${entry#"$path/"}"
        if [[ -L "$entry" ]];then printf '%s|l|%s\n' "$relative" "$(readlink "$entry" | apply_hash)"
        elif [[ -f "$entry" ]];then printf '%s|f|%s\n' "$relative" "$(apply_hash < "$entry")"
        elif [[ -d "$entry" ]];then printf '%s|d\n' "$relative"
        else printf 'error: unsupported filesystem entry: %s\n' "$entry" >&2;return 1;fi
      done <<< "$entries"
    } | apply_hash | { IFS= read -r hash;printf 'd:%s\n' "$hash"; }
  elif apply_exists "$path"; then printf 'error: unsupported filesystem entry: %s\n' "$path" >&2;return 1
  else printf 'absent\n';fi
}

apply_state() {
  local content
  content="$(apply_content "$1")" || return
  if [[ "$content" == absent ]];then printf 'absent\n'
  else printf '%s:%s\n' "$(apply_stat "$1")" "$content";fi
}

apply_nearest_directory() {
  local path="$1"
  while ! [[ -d "$path" && ! -L "$path" ]]; do
    [[ "$path" != / ]] || return 1
    path="$(dirname -- "$path")"
  done
  printf '%s\n' "$path"
}

# An explicitly supplied root is trusted and canonicalized once. Descendants
# are never traversed through symlinks; conflicts become planned replacements.
apply_resolve_root() {
  local path="$1" parent suffix=''
  apply_safe_path "$path" || return
  [[ "$path" == /* ]] || path="$PWD/$path"
  case "$path/" in */../*|*/./*) printf 'error: root must not contain dot segments\n' >&2;return 1 ;; esac
  while ! [[ -d "$path" ]]; do
    if apply_exists "$path"; then printf 'error: root is not a directory: %s\n' "$path" >&2;return 1;fi
    parent="$(dirname -- "$path")"
    [[ "$parent" != "$path" ]] || return 1
    suffix="/$(basename -- "$path")$suffix";path="$parent"
  done
  path="$(cd -- "$path" && pwd -P)" || return
  if [[ "$path" == / && -z "$suffix" ]];then printf '/\n';else printf '%s%s\n' "${path%/}" "$suffix";fi
}

apply_parent_safe() {
  local root="$1" target="$2" path relative segment parts=()
  [[ "$target" == "$root" || "$target" == "${root%/}/"* ]] || { printf 'error: target outside root: %s\n' "$target" >&2;return 1; }
  path="$root"
  if [[ -L "$path" || ! -d "$path" ]]; then printf 'error: deployment root changed: %s\n' "$path" >&2;return 1;fi
  relative="${target#"${root%/}/"}"
  [[ "$target" != "$root" ]] || return 0
  IFS=/ read -r -a parts <<< "$relative"
  for ((segment=0;segment<${#parts[@]}-1;segment++));do
    path="$path/${parts[segment]}"
    if [[ -L "$path" || ! -d "$path" ]];then printf 'error: unsafe parent: %s\n' "$path" >&2;return 1;fi
  done
}
