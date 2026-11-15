# Legacy declaration adapter. Called only after raw input validation.
function normalize_legacy_fields() {
  if(value["environments"]=="") value["environments"]=(value["scope"]=="desktop" ? "native" : "native wsl")
  value["probe_command"]=value["check"]
  delete value["scope"];delete value["check"]
  if(value["methods"]=="") value["methods"]=value["method"]
  if(value["preferred_method"]=="") value["preferred_method"]=value["method"]
}
