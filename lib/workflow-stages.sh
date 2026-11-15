# shellcheck shell=bash
workflow_stages_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# The registry is data: handlers are identifiers, never shell expressions.
workflow_stage_plan() {
  local platform="$1" profile="$2" only="$3" from="$4" mirrors="$5"
  local registry="${6:-$workflow_stages_library_dir/../workflow/schema/stages.tsv}"
  [[ -z "$only" || -z "$from" ]] || { printf 'error: --only-stage and --from-stage are mutually exclusive\n' >&2; return 2; }
  # macOS awk rejects literal newlines in -v assignments; ENVIRON preserves the profile as data.
  LC_ALL=C DOTFILES_STAGE_PROFILE="$profile" awk -F '\t' -v platform="$platform" -v only="$only" -v from="$from" -v mirrors="$mirrors" '
    function fail(message) {print "workflow stages: " message > "/dev/stderr";bad=1;exit 1}
    BEGIN {n=split(ENVIRON["DOTFILES_STAGE_PROFILE"],lines,"\n");for(i=1;i<=n;i++){p=index(lines[i],"=");settings[substr(lines[i],1,p-1)]=substr(lines[i],p+1)}}
    {sub(/\r$/, "")}
    /^#/ || /^$/ {next}
    {if(NF!=6 || $1 !~ /^(unix|windows)$/ || $2 !~ /^[0-9]+$/ || length($2)>6 || $3 !~ /^[a-z][a-z0-9-]*$/ || $4 !~ /^(always|install|components|mirrors|shell|wsl)$/ || $5 !~ /^(packages|git|configuration|mirrors|shell|wsl)$/ || $6 !~ /^(packages|git|configuration|mirrors|shell|wsl)$/) fail("invalid registry row")
      if($1=="unix" && ($5 ~ /^(git|wsl)$/ || $6 ~ /^(git|wsl)$/)) fail("unsupported Unix handler")
      if($1=="windows" && ($5 ~ /^(mirrors|shell)$/ || $6 ~ /^(mirrors|shell)$/)) fail("unsupported Windows handler")
      if(seen[$1 SUBSEP $3]++) fail("duplicate stage " $3)
      if($1==platform){ids[++count]=$3;orders[$3]=$2+0;gate[$3]=$4;preflight[$3]=$5;action[$3]=$6}}
    END {
      if(bad) exit 1
      if(!count) fail("unknown platform " platform)
      if(only!="" && !((platform SUBSEP only) in seen)) fail("unknown stage " only)
      if(from!="" && !((platform SUBSEP from) in seen)) fail("unknown stage " from)
      reached=(from=="")
      for(i=1;i<=count;i++) {
        best=""
        for(j=1;j<=count;j++) {id=ids[j];if(!(id in done) && (best=="" || orders[id]<orders[best] || (orders[id]==orders[best] && id<best))) best=id}
        done[best]=1;if(best==from) reached=1
        enabled=(reached && (only=="" || best==only));reason=(enabled ? "" : "selection")
        if(enabled && gate[best]!="always" && gate[best]!="mirrors" && settings[gate[best]]=="none") {enabled=0;reason="profile"}
        if(enabled && gate[best]=="mirrors" && mirrors==0) {enabled=0;reason="disabled"}
        print best "|" enabled "|" reason "|" preflight[best] "|" action[best]
      }
    }
  ' "$registry"
}

workflow_stage_enabled() {
  local context="$1" stage="$2"
  awk -F '|' -v stage="$stage" '$1==stage && $2==1 {found=1} END {exit !found}' "$context/stages.plan"
}
