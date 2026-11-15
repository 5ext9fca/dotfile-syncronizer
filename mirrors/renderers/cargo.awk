function render(text) {
    if(text ~ /^\[/) section=text
    if(section=="[source.rsproxy-sparse]" && text ~ /^[ \t]*registry[ \t]*=/) text="registry = \"" values["cargo_index"] "\""
    if(section=="[registries.rsproxy]" && text ~ /^[ \t]*index[ \t]*=/) text="index = \"" values["cargo_index"] "\""
  return text
}
function finish() {
}
