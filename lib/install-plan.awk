# Shared-schema parser and deterministic dependency planner (POSIX awk).
function fail(message) {
  print "install config: " message " (" FILENAME ":" FNR ")" > "/dev/stderr"
  invalid=1
  exit 1
}
function contains(words, word) { return index(" " words " ", " " word " ") != 0 }
function clear_values( k) { for (k in value) delete value[k] }
function validate_entry( m,k,required,n,i,kind,allowed) {
  if (!section) return
  m=value["method"];kind=value["source_kind"]
  if (!(m in methods) || !contains(platforms[m],section)) fail("unsupported method " m " for " section)
  if (value["order"] == "" || length(value["order"])>6) fail("order must be 0..999999")
  if (!(kind in sources) || !contains(kinds[m],kind)) fail("unsupported source_kind " kind " for " m)
  n=split("order method source_kind " requirements[m] " " sources[kind],required," ")
  for (i=1;i<=n;i++) if (required[i]!="" && value[required[i]]=="") fail("missing " required[i])
  allowed="order method source_kind scope check depends_on install_depends_on environments provides wsl_provider methods preferred_method detect_files detect_dirs " requirements[m] " " options[m] " " sources[kind]
  if (sources[kind]=="source_url") allowed=allowed " mirror_url"
  for (k in value) {
    if (!contains(allowed,k)) fail("field " k " is not supported by " m "/" kind)
    if (value[k]!="" && value[k] !~ ("^(" patterns[k] ")$")) fail("invalid " k)
  }
  if ((m=="winget" || m=="msvc" || m=="rustup" || m=="pipx") && value["packages"] ~ / /) fail(m " requires one package/toolchain")
  if (kind!="cargo-index" && (value["source_url"] ~ /^sparse/ || value["mirror_url"] ~ /^sparse/)) fail("sparse+ URLs require cargo-index")
  if(m=="font-download") {
    if(value["source_url"] !~ /^https:\/\// || value["mirror_url"]!="") fail("font-download requires HTTPS and does not support mirrors")
    n=split(value["font_files"],required," ")
    for(i=1;i<=n;i++) for(k=1;k<i;k++) if(required[i]==required[k]) fail("duplicate font filename")
  }
  if(value["provides"]!="" && !(value["provides"] in capabilities)) fail("unknown runtime capability")
  if(value["scope"]!="" && value["environments"]!="") fail("scope and environments cannot be combined")
  if(value["wsl_provider"]!="") {
    if(section !~ /^linux\./ || value["environments"]!="native") fail("WSL provider requires native-only Linux installation")
    if(!(value["wsl_provider"] in provider_capability) || value["provides"]!=provider_capability[value["wsl_provider"]]) fail("unknown or mismatched runtime provider")
  }
}
function store_entry( identity,record,i) {
  identity=section SUBSEP id
  if (identity in records) fail("duplicate item/section " id "/" section)
  normalize_legacy_fields()
  value["order"]+=0
  record=id
  for(i=1;i<=field_count;i++) record=record "|" value[fields[i]]
  records[identity]=record
  orders[identity]=value["order"]
  dependencies[identity]=value["depends_on"]
  environments[identity]=value["environments"]
  if(value["wsl_provider"]!="") environments[identity]=environments[identity] " wsl"
  item_ids[identity]=id
  item_platforms[identity]=section
}

# Kahn topological sort: among ready nodes choose numeric order then ASCII ID.
function sort_platform(p,   k,n,i,d,dep,ready,best,count,done_count) {
  for(k in done) delete done[k]
  count=0;done_count=0
  for(k in records) if(item_platforms[k]==p) {
    count++
    n=split(dependencies[k],dep," ")
    for(i=1;i<=n;i++) {
      d=p SUBSEP dep[i]
      if(!(d in records)) fail("missing dependency " dep[i] " for " item_ids[k] " on " p)
      if(contains(environments[k],"native") && !contains(environments[d],"native")) fail("dependency unavailable in native environment")
      if(contains(environments[k],"wsl") && !contains(environments[d],"wsl")) fail("dependency unavailable in WSL environment")
      for(j=1;j<i;j++) if(dep[j]==dep[i]) fail("duplicate dependency " dep[i])
    }
  }
  while(done_count<count) {
    best=""
    for(k in records) if(item_platforms[k]==p && !(k in done)) {
      ready=1;n=split(dependencies[k],dep," ")
      for(i=1;i<=n;i++) if(!((p SUBSEP dep[i]) in done)) ready=0
      if(ready && (best=="" || orders[k]<orders[best] || (orders[k]==orders[best] && item_ids[k]<item_ids[best]))) best=k
    }
    if(best=="") fail("dependency cycle on " p)
    done[best]=1;done_count++
    if(p==platform) output[++output_count]=records[best]
  }
}
FILENAME==ARGV[1] {
  if(/^#/ || /^$/) next
  split($0,columns,"\t");patterns[columns[1]]=columns[2];next
}
FILENAME==ARGV[2] {
  if(/^#/ || /^$/) next
  split($0,columns,"\t");m=columns[1];methods[m]=1;platforms[m]=columns[2];requirements[m]=columns[3];kinds[m]=columns[4];options[m]=(columns[5]=="-" ? "" : columns[5]);next
}
FILENAME==ARGV[3] {
  if(/^#/ || /^$/) next
  split($0,columns,"\t");sources[columns[1]]=(columns[2]=="-" ? "" : columns[2]);next
}
FILENAME==ARGV[4] {
  if(/^#/ || /^$/) next
  split($0,columns,"\t");provider_capability[columns[1]]=columns[2];next
}
FILENAME==ARGV[5] {
  if(/^#/ || /^$/) next
  if($0 !~ /^[a-z][a-z0-9-]*$/) fail("invalid runtime capability");capabilities[$0]=1;next
}
FILENAME==ARGV[6] {
  if(/^#/ || /^$/) next
  split($0,columns,"\t");discovery_roots[columns[1]]=1;discovery_platforms[columns[1]]=columns[2];discovery_kinds[columns[1]]=columns[3];next
}
FILENAME==ARGV[7] {
  if(!contains("id action reason source_origin state schema_version",$0)) fields[++field_count]=$0
  next
}
FNR==1 {
  finish_file();section=""
  id=FILENAME;sub(/^.*\//,"",id);sub(/\.conf$/,"",id)
  if(id !~ /^[a-z0-9][a-z0-9-]*$/) fail("invalid item filename")
}
{
  sub(/\r$/,"");sub(/^[ \t]+/,"");sub(/[ \t]+$/,"")
  if($0=="" || /^#/) next
  if(/^\[/) {
    if($0 !~ /^\[(macos|windows|linux\.(apt|dnf|pacman))(\/[a-z][a-z-]*)?\]$/) fail("unknown platform section")
    section=substr($0,2,length($0)-2)
    if(section in sections) fail("duplicate section " section)
    sections[section]=1;next
  }
  if(!section || !index($0,"=")) fail("expected key=value inside a section")
  k=substr($0,1,index($0,"=")-1);v=substr($0,index($0,"=")+1)
  if(!(k in patterns)) fail("unknown field " k)
  if((section SUBSEP k) in entries) fail("duplicate field " k)
  if(v ~ /[|\t]/) fail("pipes and tabs are not allowed")
  entries[section SUBSEP k]=v
}
END {
  if(invalid) exit 1
  finish_file()
  split("linux.apt linux.dnf linux.pacman macos windows",all_platforms," ")
  if(!contains("linux.apt linux.dnf linux.pacman macos windows",platform)) fail("unknown target platform")
  for(p=1;p<=5;p++) sort_platform(all_platforms[p])
  for(i=1;i<=output_count;i++) print output[i]
}
