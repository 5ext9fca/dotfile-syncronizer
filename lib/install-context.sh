# shellcheck shell=bash
# Context format: platform|dry-run|brew executable|brew prefix|backup root
# Fields 6..8: active mechanism (set by dispatch), distribution ID, codename.
# Linux entry detection supplies distribution facts for vendor repositories.
install_context_make() {
  local part separator=''
  for part in "$@"; do
    if [[ "$part" == *'|'* || "$part" == *$'\n'* || "$part" == *$'\r'* ]]; then
      printf 'error: execution context values cannot contain pipes or newlines\n' >&2
      return 1
    fi
  done
  for part in "$@"; do printf '%s%s' "$separator" "$part"; separator='|'; done
  printf '\n'
}

install_context() {
  printf '%s\n' "$1" | cut -d '|' -f "$2"
}

