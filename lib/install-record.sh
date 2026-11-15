# shellcheck shell=bash
# Plan field order and versions belong exclusively to the data contract.
install_field_names="$(contract_fields install-plan | tr '|' ' ')"
install_field() {
  local record="$1" field="$2"
  printf '%s\n' "$record" | awk -F '|' -v fields="$install_field_names" -v wanted="$field" '
    BEGIN {n=split(fields,names," ");for(i=1;i<=n;i++) if(names[i]==wanted) column=i;if(!column) exit 1}
    {print $column}'
}
install_record_update() {
  local record="$1" key value updates=''
  shift
  [[ "$record" != *$'\n'* && $# -gt 0 && $(( $# % 2 )) == 0 ]] || return 2
  while (( $# ));do
    key="$1";value="$2";shift 2
    [[ "$key" =~ ^[a-z][a-z_]*$ && "$value" != *'|'* && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *$'\t'* ]] || return 2
    updates="$updates$key=$value"$'\n'
  done
  printf '%s\n' "$record" | DOTFILES_INSTALL_UPDATES="$updates" awk -F '|' -v OFS='|' -v fields="$install_field_names" '
    BEGIN {
      n=split(fields,names," ");for(i=1;i<=n;i++) col[names[i]]=i
      count=split(ENVIRON["DOTFILES_INSTALL_UPDATES"],pairs,"\n")
      for(i=1;i<count;i++) {pos=index(pairs[i],"=");key=substr(pairs[i],1,pos-1)
        if(!(key in col) || key in changes) exit 2
        changes[key]=substr(pairs[i],pos+1)}
    }
    {for(key in changes) $(col[key])=changes[key];print}'
}
