# shellcheck shell=bash
# The complete current-state resume observation, including environment gates,
# belongs to the shared core.
install_resume_record() { install_evaluate_record "$1" "$2" resume; }
