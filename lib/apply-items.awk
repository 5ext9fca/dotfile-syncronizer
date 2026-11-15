function fail(message) { print "apply config: " message " (" FILENAME ":" FNR ")" > "/dev/stderr"; invalid=1;exit 1 }
function relative(path, n,parts,i) {
  if(path=="" || path ~ /^[\/]/ || path ~ /[:\\]/) return 0
  n=split(path,parts,"/")
  for(i=1;i<=n;i++) if(parts[i]=="" || parts[i]=="." || parts[i]=="..") return 0
  return 1
}
function emit( k,n,i,parts) {
  if(section=="") return
  for(k in pattern) {
    if(required[k]=="yes" && value[k]=="") fail("missing " k)
    if(value[k]!="" && value[k] !~ ("^(" pattern[k] ")$")) fail("invalid " k)
  }
  if(!relative(value["source"]) || !relative(value["target"])) fail("source and target must be relative paths without dot segments")
  if(section=="unix" && value["target_root"]!="config_home" && value["target_root"]!="home") fail("Unix requires home or config_home")
  if(section=="windows" && (value["target_root"] !~ /^(home|app_data|local_app_data)$/ || value["method"]!="copy")) fail("Windows requires home, app_data or local_app_data and copy")
  if(value["renderer"]!="" && (section!="unix" || value["target_root"]!="config_home" || value["condition"]!="linux-kde" || value["method"]!="hardlink")) fail("desktop-fonts requires Unix config_home linux-kde hardlink")
  if(section=="windows" && value["condition"]!="") fail("conditions are Unix-only")
  n=split(value["exclude"],parts,";")
  for(i=1;i<=n;i++) if(!relative(parts[i])) fail("invalid exclusion")
  if(seen[id SUBSEP section]++) fail("duplicate section")
  if(section==platform) rows[id]=id "|" value["source"] "|" value["target_root"] "|" value["target"] "|" value["method"] "|" value["exclude"] "|" value["condition"] "|" value["renderer"]
}
FILENAME==ARGV[1] {
  if(/^#/ || /^$/) next
  split($0,parts,"\t");pattern[parts[1]]=parts[2];required[parts[1]]=parts[3];next
}
FNR==1 {
  emit();for(k in value) delete value[k];section=""
  id=FILENAME;sub(/^.*\//,"",id);sub(/\.conf$/,"",id)
  if(id !~ /^[a-z0-9][a-z0-9-]*$/) fail("invalid component ID")
}
{
  sub(/\r$/,"");sub(/^[ \t]+/,"");sub(/[ \t]+$/,"")
  if(/^#/ || /^$/) next
  if(/^\[/) {
    emit();for(k in value) delete value[k]
    if($0 !~ /^\[(unix|windows)\]$/) fail("unknown platform")
    section=substr($0,2,length($0)-2);next
  }
  if(!section || !index($0,"=")) fail("expected key=value in a section")
  k=substr($0,1,index($0,"=")-1);v=substr($0,index($0,"=")+1)
  if(!(k in pattern) || k in value) fail("unknown or duplicate field " k)
  if(v ~ /[|\t]/) fail("tabs and pipes are not supported")
  value[k]=v
}
END {
  if(invalid) exit 1
  emit()
  for(id in rows) print rows[id]
}
