# Keep common edges even when a recipe lists the same dependency.
function installation_dependencies(common,specific,   n,ids,i,result) {
  n=split(specific,ids," ")
  for(i=1;i<=n;i++) if(!contains(common,ids[i])) result=result (result!="" ? " " : "") ids[i]
  return result
}
# Merge two independently validated dependency lists. Shared edges occur once.
function merge_dependencies(common, specific,   scope,n,ids,i,j,result,text) {
  for(scope=1;scope<=2;scope++) {
    text=(scope==1 ? common : specific)
    if(text!="" && text !~ ("^(" patterns["depends_on"] ")$")) fail("invalid depends_on")
    n=split(text,ids," ")
    for(i=1;i<=n;i++) {
      for(j=1;j<i;j++) if(ids[i]==ids[j]) fail("duplicate dependency " ids[i])
      if(!contains(result,ids[i])) result=result (result!="" ? " " : "") ids[i]
    }
  }
  return result
}
# Typed paths are literal data, never shell expressions or glob patterns.
function discovery_paths(method,kind,text,   n,paths,i,pos,root,path,parts,j,total,result) {
  if(text=="") return ""
  n=split(text,paths,";")
  for(i=1;i<=n;i++) {
    pos=index(paths[i],":");root=substr(paths[i],1,pos-1);path=substr(paths[i],pos+1)
    if(!pos || !(root in discovery_roots)) fail("unknown discovery root")
    if(!contains(discovery_platforms[root],section) || !contains(discovery_kinds[root],kind)) fail("unsupported discovery root for platform/type")
    if(path=="" || path ~ /[\\|;:*?<>"\t]/ || path ~ /^\// || path ~ /\/$/) fail("invalid discovery path")
    total=split(path,parts,"/")
    for(j=1;j<=total;j++) if(parts[j]=="" || parts[j]=="." || parts[j]=="..") fail("invalid discovery path segment")
    if(root=="path" && (kind!="file" || total!=1)) fail("path discovery requires a filename")
    result=result (result!="" ? ";" : "") method ":" kind ":" paths[i]
  }
  return result
}
function load_section(name,   k,parts) {
  for(k in entries) {split(k,parts,SUBSEP);if(parts[1]==name) value[parts[2]]=entries[k]}
}
function finish_file( name,k,parts,p,variant,n,list,i,j,preferred,common,compiled,fragment) {
  if(id=="") return
  for(name in sections) {
    split(name,parts,"/");p=parts[1]
    if(index(name,"/")) {
      if(!(p in sections) || !contains(entries[p SUBSEP "methods"],parts[2])) fail("undeclared installation method section " name)
      continue
    }
    section=p;clear_values();load_section(p)
    if(value["methods"]=="") {
      if(value["preferred_method"]!="") fail("preferred_method requires methods")
      validate_entry()
      common=value["depends_on"]
      value["depends_on"]=merge_dependencies(common,value["install_depends_on"])
      value["install_depends_on"]=installation_dependencies(common,value["install_depends_on"])
      compiled=discovery_paths(value["method"],"file",value["detect_files"])
      fragment=discovery_paths(value["method"],"directory",value["detect_dirs"])
      value["discovery"]=compiled (compiled!="" && fragment!="" ? ";" : "") fragment
      if(value["discovery"]!="" && value["check"]!="") fail("check cannot be combined with discovery")
      store_entry();continue
    }
    common="order methods preferred_method depends_on environments provides wsl_provider scope"
    for(k in value) if(!contains(common,k)) fail("method-specific field in common section: " k)
    preferred=value["preferred_method"];n=split(value["methods"],list," ")
    if(preferred=="" || preferred=="manual" || !contains(value["methods"],preferred)) fail("invalid preferred_method")
    compiled=""
    for(i=1;i<=n;i++) {
      variant=list[i]
      for(j=1;j<i;j++) if(list[j]==variant) fail("duplicate installation method")
      if(!((p "/" variant) in sections)) fail("missing method section " variant)
      clear_values();load_section(p);load_section(p "/" variant)
      for(k in entries) {
        split(k,parts,SUBSEP)
        if(parts[1]==p "/" variant && ((contains(common,parts[2]) && parts[2]!="depends_on") || parts[2]=="method" || parts[2]=="check" || parts[2]=="install_depends_on")) fail("invalid method subsection field " parts[2])
      }
      if(variant=="manual" && ((p "/" variant SUBSEP "depends_on") in entries)) fail("manual cannot declare installation dependencies")
      value["depends_on"]=merge_dependencies(entries[p SUBSEP "depends_on"],entries[p "/" variant SUBSEP "depends_on"])
      value["method"]=variant
      if(value["detect_files"]=="" && value["detect_dirs"]=="") fail("installation method requires discovery paths")
      if(variant=="manual") {
        for(k in value) if(!contains(common " method detect_files detect_dirs",k)) fail("manual is discovery-only")
      } else validate_entry()
      fragment=discovery_paths(variant,"file",value["detect_files"])
      if(fragment!="") {compiled=compiled (compiled!="" ? ";" : "") fragment}
      fragment=discovery_paths(variant,"directory",value["detect_dirs"])
      if(fragment!="") {compiled=compiled (compiled!="" ? ";" : "") fragment}
    }
    clear_values();load_section(p);load_section(p "/" preferred);value["method"]=preferred
    value["depends_on"]=merge_dependencies(entries[p SUBSEP "depends_on"],entries[p "/" preferred SUBSEP "depends_on"])
    validate_entry()
    value["install_depends_on"]=installation_dependencies(entries[p SUBSEP "depends_on"],entries[p "/" preferred SUBSEP "depends_on"])
    value["discovery"]=compiled;store_entry()
  }
  for(k in sections) delete sections[k]
  for(k in entries) delete entries[k]
  clear_values()
}

