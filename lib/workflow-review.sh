# shellcheck shell=bash
workflow_review_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=stage-result.sh
source "$workflow_review_library_dir/stage-result.sh"
# shellcheck source=install-report.sh
source "$workflow_review_library_dir/install-report.sh"
workflow_show_status() { dotfiles_request workflow-status session "$1" style unix; }

workflow_request_read() { dotfiles_request workflow-request-read session "$1"; }
