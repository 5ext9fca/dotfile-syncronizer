# Render known mirror settings while preserving unrelated lines and repositories.
function replace_literal(text,old,new, at,result,tail) {
  if(old=="" || old==new) return text
  result=""
  while((at=index(text,old))>0) {
    tail=substr(text,at+length(old),1)
    if(tail=="" || tail=="/" || tail ~ /[[:space:]]/ || tail=="\"") result=result substr(text,1,at-1) new
    else result=result substr(text,1,at-1) old
    text=substr(text,at+length(old))
  }
  return result text
}
function endpoint(text,key,legacy) {
  if(mode=="apply") {
    text=replace_literal(text,legacy,values[key])
    if(key in previous) text=replace_literal(text,previous[key],values[key])
  }
  return text
}
FILENAME==ARGV[1] {
  if(/^#/ || /^$/) next
  at=index($0,"=");values[substr($0,1,at-1)]=substr($0,at+1);next
}
FILENAME==ARGV[2] {
  if(/^#/ || /^$/) next
  at=index($0,"=");previous[substr($0,1,at-1)]=substr($0,at+1);next
}
FILENAME==ARGV[3] {
  if(/^#/ || /^$/) next
  at=index($0,"=");legacy[substr($0,1,at-1)]=substr($0,at+1);next
}
{ print render($0) }
END { finish() }
