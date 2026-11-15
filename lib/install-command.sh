# shellcheck shell=bash
# shellcheck source=command.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/command.sh"
# shellcheck source=install-policy.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/install-policy.sh"
# Commands receive an explicit context; dry runs never invoke the command.
install_run() {
  local context="$1" policy code=0
  shift
  policy="$(install_execution_policy "$(install_context "$context" 6)" install)" || return
  command_run mutation "$(install_context "$context" 2)" "${policy%%|*}" '' -- "$@" || code=$?
  case ",${policy#*|}," in *",$code,"*) return 0 ;; *) return "$code" ;; esac
}
