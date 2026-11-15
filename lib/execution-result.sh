# shellcheck shell=bash
execution_result_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
execution_result() {
  local code="$1" dry="$2" row
  [[ "$code" =~ ^[0-9]+$ && "$dry" =~ ^[01]$ ]] || return 1
  if [[ "$code" == 0 && "$dry" == 1 ]];then printf 'planned|dry-run\n';return;fi
  row="$(awk -F '\t' -v code="$code" '$1==code {print $2 "|" $3}' "$execution_result_library_dir/../workflow/schema/outcomes.tsv")"
  if [[ -n "$row" ]];then printf '%s\n' "$row";else printf 'failed|exit-%s\n' "$code";fi
}
