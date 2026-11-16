# shellcheck shell=bash
# Compatibility signatures delegate complete planning requests to Python.
apply_read_items() {
  dotfiles_request apply-items directory "$1" platform "$2"
}

apply_make_plan() {
  dotfiles_request apply-plan-native style unix native_shell "$BASH" repo "$1" items "$2" config "$3" session "$4" selection "$5" render_scratch "${6:-}" preview "${7:-0}" roots "${8:-$(printf 'home|%s\nconfig_home|%s\n' "${HOME:-}" "$3")}"
}
