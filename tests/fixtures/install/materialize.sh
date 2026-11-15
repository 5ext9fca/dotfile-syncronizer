# shellcheck shell=bash
materialize_install_fixture() {
  local root="$1" name="$2" destination="$3"
  if [[ ! -f "$root/$name/edits.tsv" ]];then printf '%s\n' "$root/$name";return;fi
  mkdir -p "$destination/$name"
  awk -f "$root/materialize.awk" "$root/$name/edits.tsv" "$root/discovery/tool.conf" > "$destination/$name/tool.conf" || return
  printf '%s\n' "$destination/$name"
}
