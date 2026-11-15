. (Join-Path $PSScriptRoot 'data-contract.ps1')
. (Join-Path $PSScriptRoot 'atomic-report.ps1')
. (Join-Path $PSScriptRoot 'install-discovery.ps1')
. (Join-Path $PSScriptRoot 'install-normalize.ps1')
. (Join-Path $PSScriptRoot 'install-compat.ps1')
# Shared-schema configuration, dependency planning and execution for PowerShell 5.1+.
$InstallSchemaDirectory = Join-Path $PSScriptRoot '../install/schema'

. (Join-Path $PSScriptRoot 'install-config.ps1')

. (Join-Path $PSScriptRoot 'install-probe.ps1')

. (Join-Path $PSScriptRoot 'install-plan.ps1')

. (Join-Path $PSScriptRoot 'execution-result.ps1')
. (Join-Path $PSScriptRoot 'install-command.ps1')

. (Join-Path $PSScriptRoot 'install-execute.ps1')

. (Join-Path $PSScriptRoot '../install/handlers/windows.ps1')
. (Join-Path $PSScriptRoot 'install-state.ps1')
. (Join-Path $PSScriptRoot 'install-decision.ps1')
. (Join-Path $PSScriptRoot 'install-report.ps1')
