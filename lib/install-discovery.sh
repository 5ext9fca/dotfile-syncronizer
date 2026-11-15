# shellcheck shell=bash
# File-system-only discovery. No application or package-manager command is run.
install_discovery_root() {
  local root="$1" context="$2"
  case "$root" in
    home) printf '%s\n' "$HOME" ;;
    applications) printf '/Applications\n' ;;
    brew_prefix) install_context "$context" 4 ;;
    root) printf '/\n' ;;
    *) return 2 ;;
  esac
}
# A matched path is JSON-encoded before crossing the line-oriented boundary.
# Encoding also protects the outer report delimiter and unusual root characters.
install_discovery_path_json() {
  local path="$1"
  [[ "$path" == /* ]] || path="$PWD/$path"
  DOTFILES_DISCOVERY_PATH="$path" LC_ALL=C awk 'BEGIN {
    for(i=1;i<32;i++) escapes[sprintf("%c",i)]=sprintf("\\u%04x",i)
    escapes["\""]="\\\"";escapes["\\"]="\\\\";escapes["|"]="\\u007c"
    text=ENVIRON["DOTFILES_DISCOVERY_PATH"];printf "\""
    for(i=1;i<=length(text);i++) {c=substr(text,i,1);printf "%s",(c in escapes ? escapes[c] : c)}
    printf "\""
  }'
}
# Distinguish an inaccessible ancestor from a genuinely missing path.
install_discovery_accessible() {
  local path="$1" parent
  [[ "$path" == /* ]] || path="$PWD/$path"
  parent="${path%/*}"
  while [[ -n "$parent" ]];do
    if [[ -d "$parent" && ! -x "$parent" ]];then
      printf 'error: cannot inspect discovery path: %s\n' "$path" >&2;return 2
    fi
    [[ "$parent" != / ]] || break
    parent="${parent%/*}";[[ -n "$parent" ]] || parent=/
  done
}
install_discovery_match_path() {
  local kind="$1" root="$2" relative="$3" context="$4" base path_part
  if [[ "$root" == path ]];then
    [[ "$kind" == file && "$relative" != */* ]] || return 2
    while IFS= read -r path_part;do
      [[ -n "$path_part" ]] || continue
      install_discovery_accessible "$path_part/$relative" || return
      if [[ -f "$path_part/$relative" ]];then install_discovery_path_json "$path_part/$relative";return;fi
    done < <(printf '%s\n' "$PATH" | tr ':' '\n')
    return 1
  fi
  base="$(install_discovery_root "$root" "$context")" || return
  [[ -n "$base" ]] || return 1
  install_discovery_accessible "$base/$relative" || return
  case "$kind" in
    file) [[ -f "$base/$relative" ]] || return 1 ;;
    directory) [[ -d "$base/$relative" ]] || return 1 ;;
    *) return 2 ;;
  esac
  install_discovery_path_json "${base%/}/$relative"
}
install_discovery_path_exists() { install_discovery_match_path "$@" >/dev/null; }
install_discovery_observation() {
  local record="$1" context="$2" spec method kind root relative candidate seen=' ' matches code paths path
  spec="$(install_field "$record" discovery)"
  # Each method is one conjunction of paths; methods are alternatives.
  while IFS=: read -r method kind root relative;do
    [[ -n "$method" && "$seen" != *" $method "* ]] || continue
    seen="$seen$method "
    matches=1;paths=''
    while IFS=: read -r candidate kind root relative;do
      [[ "$candidate" == "$method" ]] || continue
      if path="$(install_discovery_match_path "$kind" "$root" "$relative" "$context")";then
        paths="$paths${paths:+,}$path"
      else code=$?;[[ "$code" == 1 ]] || return "$code";matches=0;fi
    done < <(printf '%s\n' "$spec" | tr ';' '\n')
    if [[ "$matches" == 1 ]];then printf '%s|[%s]\n' "$method" "$paths";return 0;fi
  done < <(printf '%s\n' "$spec" | tr ';' '\n')
  printf '|\n'
}
install_discover() {
  local observation method
  observation="$(install_discovery_observation "$1" "$2")" || return
  method="${observation%%|*}"
  [[ -z "$method" ]] || printf 'discovered:%s\n' "$method"
  return 0
}
