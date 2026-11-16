# shellcheck shell=bash
workflow_stages_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=python.sh
source "$workflow_stages_library_dir/python.sh"
workflow_stage_plan() {
  dotfiles_python stage-plan --platform="$1" --profile="$2" --only="$3" --from-stage="$4" --mirrors="$5" --registry="${6:-$workflow_stages_library_dir/../workflow/schema/stages.tsv}"
}

workflow_stage_enabled() {
  local context="$1" stage="$2"
  awk -F '|' -v stage="$stage" '$1==stage && $2==1 {found=1} END {exit !found}' "$context/stages.plan"
}
