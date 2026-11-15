function render(text) {
    text=replace_literal(text,"http://archive.ubuntu.com/ubuntu",values["ubuntu"])
    text=replace_literal(text,"https://archive.ubuntu.com/ubuntu",values["ubuntu"])
    text=replace_literal(text,"http://security.ubuntu.com/ubuntu",values["ubuntu"])
    text=replace_literal(text,"https://security.ubuntu.com/ubuntu",values["ubuntu"])
    text=replace_literal(text,"http://ports.ubuntu.com/ubuntu-ports",values["ubuntu_ports"])
    text=replace_literal(text,"https://ports.ubuntu.com/ubuntu-ports",values["ubuntu_ports"])
    text=replace_literal(text,"http://deb.debian.org/debian-security",values["debian_security"])
    text=replace_literal(text,"https://deb.debian.org/debian-security",values["debian_security"])
    text=replace_literal(text,"http://security.debian.org/debian-security",values["debian_security"])
    text=replace_literal(text,"https://security.debian.org/debian-security",values["debian_security"])
    text=replace_literal(text,"http://security.debian.org",values["debian_security"])
    text=replace_literal(text,"https://security.debian.org",values["debian_security"])
    text=replace_literal(text,"http://deb.debian.org/debian",values["debian"])
    text=replace_literal(text,"https://deb.debian.org/debian",values["debian"])
    text=replace_literal(text,"http://ftp.debian.org/debian",values["debian"])
    text=replace_literal(text,"https://ftp.debian.org/debian",values["debian"])
    # Replace longer security/ports prefixes first.
    text=endpoint(text,"debian_security",legacy["debian_security"])
    text=endpoint(text,"debian",legacy["debian"])
    text=endpoint(text,"ubuntu_ports",legacy["ubuntu_ports"])
    text=endpoint(text,"ubuntu",legacy["ubuntu"])
  return text
}
function finish() {
}
