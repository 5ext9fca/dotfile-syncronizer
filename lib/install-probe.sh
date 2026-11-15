# shellcheck shell=bash
# Load declarative policy once; evaluating an observation performs no I/O.
install_probe_rules="$(cat "${install_library_dir:?}/../install/schema/probes.tsv")"
install_probe_result() {
  local state="$1" pattern action reason
  while IFS=$'\t' read -r pattern action reason;do
    [[ -n "$pattern" && "$pattern" != \#* ]] || continue
    # The patterns use a common ERE/.NET subset. Reject record delimiters first.
    [[ "$state" != *'|'* && "$state" != *$'\r'* && "$state" != *$'\n'* ]] || return 1
    if [[ "$state" =~ $pattern ]];then printf '%s|%s\n' "$action" "$reason";return;fi
  done <<< "$install_probe_rules"
  printf 'error: invalid installation probe state: %s\n' "$state" >&2
  return 1
}
