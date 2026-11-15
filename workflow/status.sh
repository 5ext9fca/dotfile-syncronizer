#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 ]] || { printf 'Usage: status.sh SESSION_DIRECTORY\n' >&2;exit 2; }
# shellcheck source=../lib/workflow-review.sh
source "$(cd -- "$(dirname -- "$0")/../lib" && pwd -P)/workflow-review.sh"
workflow_show_status "$1"
