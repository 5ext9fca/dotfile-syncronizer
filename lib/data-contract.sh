# shellcheck shell=bash
contract_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=python.sh
source "$contract_library_dir/python.sh"
contract_fields() { dotfiles_request contract-fields kind "$1"; }
contract_version() { dotfiles_request contract-version kind "$1"; }
contract_read() { dotfiles_request contract-read kind "$1" text "$2"; }
contract_read_schema() { dotfiles_request contract-read-schema kind "$1" text "$2" version "$3" fields "$4"; }
contract_write() { dotfiles_request contract-write kind "$1" text "$2"; }
contract_validate_rows() { dotfiles_request contract-validate kind "$1" text "$2"; }
# Publication stays in the native atomic filesystem adapter.
contract_save() {
  local document
  document="$(contract_write "$1" "$2")" || return
  printf '%s\n' "$document" | atomic_report_write "$3"
}
