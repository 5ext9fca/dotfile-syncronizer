# shellcheck shell=bash
install_decide() {
  local discovery=0
  [[ -z "${5:-}" ]] || discovery=1
  dotfiles_python install-decision --state="$1" --mode="$2" --probe-command="$3" --command-present="$4" --discovery="$discovery"
}
