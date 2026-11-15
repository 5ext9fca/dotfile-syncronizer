# shellcheck shell=bash
# Public installer API. Bash 3.2 compatible; item/context data is passed explicitly.
install_library_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=data-contract.sh
source "$install_library_dir/data-contract.sh"
# shellcheck source=atomic-report.sh
source "$install_library_dir/atomic-report.sh"
# shellcheck source=install-record.sh
source "$install_library_dir/install-record.sh"

# shellcheck source=install-context.sh
source "$install_library_dir/install-context.sh"

# shellcheck source=install-config.sh
source "$install_library_dir/install-config.sh"

# shellcheck source=install-plan.sh
source "$install_library_dir/install-plan.sh"

# shellcheck source=install-command.sh
source "$install_library_dir/install-command.sh"
# shellcheck source=execution-result.sh
source "$install_library_dir/execution-result.sh"

# shellcheck source=install-probe.sh
source "$install_library_dir/install-probe.sh"
# shellcheck source=install-discovery.sh
source "$install_library_dir/install-discovery.sh"

# shellcheck source=install-state.sh
source "$install_library_dir/install-state.sh"

# shellcheck source=install-decision.sh
source "$install_library_dir/install-decision.sh"

# shellcheck source=install-resume.sh
source "$install_library_dir/install-resume.sh"

# shellcheck source=install-execute.sh
source "$install_library_dir/install-execute.sh"

# shellcheck source=../install/handlers/native.sh
source "$install_library_dir/../install/handlers/native.sh"
# shellcheck source=../install/handlers/language.sh
source "$install_library_dir/../install/handlers/language.sh"
# shellcheck source=../install/handlers/download.sh
source "$install_library_dir/../install/handlers/download.sh"
# shellcheck source=../install/handlers/repository.sh
source "$install_library_dir/../install/handlers/repository.sh"
# shellcheck source=../install/handlers/macos.sh
source "$install_library_dir/../install/handlers/macos.sh"
# shellcheck source=install-report.sh
source "$install_library_dir/install-report.sh"

# shellcheck source=../install/handlers/docker.sh
source "$install_library_dir/../install/handlers/docker.sh"
