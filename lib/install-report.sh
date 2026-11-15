# shellcheck shell=bash
install_report_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
install_result_row() {
  local record="$1" status="$2" elapsed="$3" reason="$4" observed="${5:-1}" field value row='' separator=''
  while IFS= read -r field;do
    case "$field" in
      id) value="$(install_field "$record" id)" ;;
      status) value="$status" ;;
      elapsed_seconds) value="$elapsed" ;;
      reason) value="$reason" ;;
      selected_method) value="$(install_field "$record" method)" ;;
      detected_method|detected_paths|decision_reason)
        value='';[[ "$observed" != 1 ]] || value="$(install_field "$record" "$field")" ;;
      *) printf 'error: unknown installation result field: %s\n' "$field" >&2;return 1 ;;
    esac
    row="$row$separator$value";separator='|'
  done < "$install_report_library_dir/../contracts/schema/install-result.fields"
  printf '%s\n' "$row"
}
install_result_read() {
  local document="$1" rows fields current_fields
  if [[ "${document%%$'\n'*}" == '# dotfiles|install-result|1' || "${document%%$'\n'*}" == $'# dotfiles|install-result|1\r' ]];then
    fields="$(paste -sd '|' "$install_report_library_dir/../contracts/schema/install-result-v1.fields")"
    rows="$(contract_read_schema install-result "$document" 1 "$fields")" || return
    # v1 contains no observation evidence; never infer it from free-text reasons.
    current_fields="$(contract_fields install-result)" || return
    if [[ -n "$rows" ]];then
      printf '%s\n' "$rows" | awk -F '|' -v old="$fields" -v current="$current_fields" '
        BEGIN {n=split(old,names,"|");for(i=1;i<=n;i++) col[names[i]]=i;count=split(current,fields,"|")}
        {for(i=1;i<=count;i++) printf "%s%s",(i>1 ? "|" : ""),(fields[i] in col ? $(col[fields[i]]) : "");printf "\n"}'
    fi
  else contract_read install-result "$document";fi
}
install_result_show() {
  local rows="$1" fields
  fields="$(contract_fields install-result)" || return
  printf '%s\n' "$rows" | awk -F '|' -v fields="$fields" '
    BEGIN {n=split(fields,names,"|");for(i=1;i<=n;i++) col[names[i]]=i}
    $col["status"]~/^(failed|deferred|interrupted|running|skipped|blocked)$/ {
      printf "  Item %s: %s (%s)\n",$col["id"],$col["status"],$col["reason"]
      if($col["selected_method"]!="") printf "    Preferred method: %s\n",$col["selected_method"]
      if($col["decision_reason"]!="") printf "    Decision: %s\n",$col["decision_reason"]
      if($col["detected_method"]!="") printf "    Matched method: %s\n    Matched paths (JSON): %s\n",$col["detected_method"],$col["detected_paths"]
    }'
}
