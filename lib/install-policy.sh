# shellcheck shell=bash
install_policy_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
install_execution_policy() {
  local method="${1:-*}" operation="$2" path="${3:-$install_policy_library_dir/../install/schema/execution.tsv}"
  LC_ALL=C awk -F '\t' -v method="$method" -v operation="$operation" '
    function fail(){print "error: invalid installation execution policy" > "/dev/stderr";bad=1;exit 1}
    FILENAME==ARGV[1] {if(!/^#/ && NF) methods[$1]=1;next}
    /^#/ || /^$/ {next}
    {sub(/\r$/, "");if(NF!=4 || ($1!="*" && !($1 in methods)) || $2!~/^(probe|install|download|modify)$/ || $3!~/^(0|[1-9][0-9]*)$/ || length($3)>5 || $3+0>86400 || seen[$1 SUBSEP $2]++) fail()
     n=split($4,codes,",");delete_seen="";for(i=1;i<=n;i++){if(codes[i]!~/^(0|[1-9][0-9]*)$/ || length(codes[i])>5 || codes[i]+0>65535 || codes[i]~/^(124|130|143)$/ || index(delete_seen,"," codes[i] ",")) fail();delete_seen=delete_seen "," codes[i] ","}
     if(!index("," $4 ",",",0,") || ($2~/^(probe|download)$/ && $4!="0")) fail()
     values[$1 SUBSEP $2]=$3 "|" $4}
    END {if(bad) exit 1;split("probe install download modify",ops," ");for(i=1;i<=4;i++) if(!(("*" SUBSEP ops[i]) in values)) fail()
      key=method SUBSEP operation;if(!(key in values)) key="*" SUBSEP operation;if(!(key in values)) fail();print values[key]}
  ' "$install_policy_library_dir/../install/schema/methods.tsv" "$path"
}
install_probe_capture() {
  local method="$1" policy
  shift
  policy="$(install_execution_policy "$method" probe)" || return
  command_capture "${policy%%|*}" "$@"
}
