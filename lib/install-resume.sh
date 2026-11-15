# shellcheck shell=bash
# Resume decisions come from current installation state, never old success rows.
install_resume_record() {
  local record="$1" context="$2" reason
  reason="$(install_field "$record" reason)"
  case "$reason" in provided-by-host:*|environment-not-selected:*) printf '%s\n' "$record";return ;; esac
  install_evaluate_record "$record" "$context" resume
}
