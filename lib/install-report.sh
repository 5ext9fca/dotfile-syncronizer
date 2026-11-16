# shellcheck shell=bash
install_result_row() {
  dotfiles_request install-result-row record "$1" status "$2" elapsed "$3" reason "$4" observed "${5:-1}"
}
install_result_read() { dotfiles_request install-result-read text "$1"; }
install_result_show() { dotfiles_request install-result-show text "$1"; }
