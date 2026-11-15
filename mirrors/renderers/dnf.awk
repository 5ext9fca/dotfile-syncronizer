function render(text) {
    if(text ~ /^metalink=.*mirrors.fedoraproject.org\/metalink/) text="#" text
    if(text ~ /^#baseurl=https?:\/\/[^\/]+\/pub\/fedora\/linux/) {match(text,/^#baseurl=https?:\/\/[^\/]+\/pub\/fedora\/linux/);text="baseurl=" values["fedora"] substr(text,RLENGTH+1)}
    text=endpoint(text,"fedora",legacy["fedora"])
  return text
}
function finish() {
}
