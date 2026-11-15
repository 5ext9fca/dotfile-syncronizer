# shellcheck shell=bash
contract_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
contract_fields() {
  local kind="$1"
  [[ "$kind" =~ ^[a-z][a-z-]*$ && -f "$contract_library_dir/../contracts/schema/$kind.fields" ]] || return 1
  paste -sd '|' "$contract_library_dir/../contracts/schema/$kind.fields"
}
contract_version() {
  awk -F '\t' -v kind="$1" '$1==kind {print $2;found=1} END {if(!found) exit 1}' "$contract_library_dir/../contracts/schema/types.tsv"
}
# Validate the complete envelope before emitting normalized rows. Column order is
# not significant on the wire; unknown/missing/duplicate columns are rejected.
contract_read() {
  local kind="$1" document="$2" fields version
  fields="$(contract_fields "$kind")" || return
  version="$(contract_version "$kind")" || return
  contract_read_schema "$kind" "$document" "$version" "$fields"
}
# Explicit historical adapters may supply a known schema; the public reader
# continues to accept only the current version for each kind.
contract_read_schema() {
  local kind="$1" document="$2" version="$3" fields="$4"
  printf '%s\n' "$document" | LC_ALL=C awk -F '|' -v kind="$kind" -v version="$version" -v fields="$fields" '
    function fail(message){print "data contract: " message > "/dev/stderr";bad=1;exit 1}
    BEGIN {count=split(fields,names,"|");for(i=1;i<=count;i++) known[names[i]]=1}
    {sub(/\r$/, "")}
    NR==1 {if($0!="# dotfiles|" kind "|" version) fail("unknown or missing " kind " version");next}
    NR==2 {if(NF!=count) fail("wrong field count");for(i=1;i<=NF;i++){if(!($i in known)||($i in positions)) fail("unknown or duplicate field");positions[$i]=i} next}
    {if(NF!=count || $0 ~ /[\r\t]/) fail("malformed record");row="";for(i=1;i<=count;i++) row=row (i>1 ? "|" : "") $(positions[names[i]]);rows[++n]=row}
    END {if(bad) exit 1;if(NR<2) fail("missing header");for(i=1;i<=n;i++) print rows[i]}
  '
}
contract_write() {
  local kind="$1" rows="$2" document fields version
  fields="$(contract_fields "$kind")" || return
  version="$(contract_version "$kind")" || return
  document="# dotfiles|$kind|$version"$'\n'"$fields"
  [[ -z "$rows" ]] || document="$document"$'\n'"$rows"
  contract_read "$kind" "$document" >/dev/null || return
  printf '%s\n' "$document"
}

contract_validate_rows() {
  local kind="$1" rows="$2" document
  document="$(contract_write "$kind" "$rows")" || return
  if [[ "$kind" == *-plan ]];then
    printf '%s\n' "$rows" | awk -F '|' -v version="$(contract_version "$kind")" 'NF && $NF!=version {bad=1} END {exit bad}' || { printf 'error: unsupported plan record version\n' >&2;return 1; }
  fi
}
contract_save() {
  local document
  document="$(contract_write "$1" "$2")" || return
  printf '%s\n' "$document" | atomic_report_write "$3"
}
