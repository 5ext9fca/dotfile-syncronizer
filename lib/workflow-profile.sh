# shellcheck shell=bash
# Both readers use the same versioned schema and never evaluate profile values.
workflow_profile_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
workflow_read_profile() {
  local path="$1"
  [[ -s "$path" ]] || { printf 'error: missing workflow profile: %s\n' "$path" >&2; return 1; }
  LC_ALL=C awk '
    function fail(message) { print "workflow profile: " message > "/dev/stderr"; bad=1; exit 1 }
    FILENAME==ARGV[1] {
      if(/^#/ || /^$/) next
      split($0,columns,"\t");key=columns[1]
      fields[++count]=key;patterns[key]=columns[2];required[key]=columns[3]
      next
    }
    { sub(/\r$/, ""); if ($0 ~ /^#/ || $0 == "") next
      pos=index($0,"="); if (!pos) fail("expected key=value")
      key=substr($0,1,pos-1); value=substr($0,pos+1)
      if(!(key in patterns)) fail("unknown field " key)
      if(key in values) fail("duplicate " key)
      if(value !~ ("^(" patterns[key] ")$")) fail("invalid " key)
      if(key=="install" && value!="none" && value!="all" && (" " value " ") ~ / (none|all) /) fail("reserved install selector")
      if(key=="components" && value!="none" && (" " value " ") ~ / none(:[^ ]*)? /) fail("reserved component selector")
      if(key=="components") {
        n=split(value,pairs," ")
        for(i=1;i<=n;i++) {
          split(pairs[i],pair,":");if(pair[1] in components) fail("duplicate component")
          components[pair[1]]=1
        }
      }
      values[key]=value
    }
    END {
      if(bad) exit 1
      for(i=1;i<=count;i++) if(required[fields[i]]=="yes" && !(fields[i] in values)) fail("missing " fields[i])
      if((values["wsl"]=="none") != (values["wsl_profile"]=="none")) fail("wsl and wsl_profile must both be enabled or none")
      for(i=1;i<=count;i++) if(fields[i] in values) print fields[i] "=" values[fields[i]]
    }
  ' "$workflow_profile_library_dir/../workflow/schema/profile-fields.tsv" "$path"
}

workflow_profile_value() {
  printf '%s\n' "$1" | awk -v key="$2" 'index($0,key "=")==1 {print substr($0,length(key)+2)}'
}

workflow_profile_components() {
  local profile="$1" plan="$2" pair component item record found action reason
  local associations
  associations="$(workflow_profile_value "$profile" components)"
  [[ "$associations" != none ]] || return 0
  for pair in $associations; do
    if [[ "$pair" != *:* ]];then printf '%s\n' "$pair";continue;fi
    component="${pair%%:*}"; item="${pair#*:}"; found=0
    while IFS= read -r record; do
      [[ "${record%%|*}" == "$item" ]] || continue
      found=1
      action="$(install_field "$record" action)"
      reason="$(install_field "$record" reason)"
      if [[ "$action" == skip && ( "$reason" == environment-not-selected:* || "$reason" == provided-by-host:* ) ]]; then
        printf 'error: component %s requires excluded install item %s\n' "$component" "$item" >&2
        return 1
      fi
    done <<< "$plan"
    (( found )) || { printf 'error: component %s requires unknown install item %s\n' "$component" "$item" >&2; return 1; }
    printf '%s\n' "$component"
  done
}

# Observe roots before expanding installation-only edges. All declarations still
# participate in schema/graph validation; unneeded recipes perform no probes.
workflow_profile_install_plan() (
  local profile="$1" plan="$2" context="${3:-}" mode="${4:-offline}" selection pending id selected=' ' record reason dependency install_dependencies action index
  local records=() ids=()
  case "$mode" in offline|normal|resume) ;; *) printf 'error: invalid selection mode\n' >&2;return 1 ;; esac
  selection="$(workflow_profile_value "$profile" install)"
  if [[ "$selection" == all ]];then selection="$(printf '%s\n' "$plan" | cut -d '|' -f1 | tr '\n' ' ')";fi
  [[ "$selection" != none ]] || return 0
  pending="$selection"
  while [[ -n "$pending" ]];do
    id="${pending%% *}";if [[ "$pending" == *' '* ]];then pending="${pending#* }";else pending='';fi
    [[ -n "$id" && "$selected" != *" $id "* ]] || continue
    record="$(printf '%s\n' "$plan" | awk -F '|' -v id="$id" '$1==id')"
    [[ -n "$record" ]] || { printf 'workflow profile: unknown install item %s\n' "$id" >&2;return 1; }
    if [[ "$mode" != offline ]];then
      reason="$(install_field "$record" reason)"
      case "$reason" in
        provided-by-host:*|environment-not-selected:*) ;;
        *) record="$(install_evaluate_record "$record" "$context" "$mode")" || return ;;
      esac
    fi
    selected="$selected$id "
    ids+=("$id");records+=("$record")
    action="$(install_field "$record" action)" || return
    install_dependencies="$(install_field "$record" install_depends_on)" || return
    for dependency in $(install_field "$record" depends_on);do
      if [[ "$action" == skip && " $install_dependencies " == *" $dependency "* ]];then continue;fi
      pending="$pending${pending:+ }$dependency"
    done
  done
  # Emit only after every selected observation succeeds, in validated order.
  while IFS='|' read -r id _;do
    for ((index=0;index<${#ids[@]};index++));do
      [[ "${ids[index]}" != "$id" ]] || printf '%s\n' "${records[index]}"
    done
  done <<< "$plan"
)

workflow_profile_path() {
  [[ "$2" =~ ^[a-z][a-z0-9-]*$ ]] || { printf 'error: invalid profile name\n' >&2;return 2; }
  printf '%s/workflow/profiles/%s.conf\n' "$1" "$2"
}
