function render(text) {
    if(text ~ /^[ \t]*registry[ \t]*=/) {text="registry=" values["npm"];found=1}
  return text
}
function finish() {
  if(!found) print "registry=" values["npm"]
}
