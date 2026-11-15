function render(text) {
    if(text ~ /^GOPROXY=/) {
      found_proxy=1
      if(mode=="apply" && (text=="GOPROXY=" previous["go_proxy"] || text=="GOPROXY=" legacy["go_proxy"])) text="GOPROXY=" values["go_proxy"]
    }
    if(text ~ /^GOSUMDB=/) {
      found_sumdb=1
      if(mode=="apply" && (text=="GOSUMDB=" previous["go_sumdb"] || text=="GOSUMDB=" legacy["go_sumdb"])) text="GOSUMDB=" values["go_sumdb"]
    }
  return text
}
function finish() {
  if(!found_proxy) print "GOPROXY=" values["go_proxy"]
  if(!found_sumdb) print "GOSUMDB=" values["go_sumdb"]
}
