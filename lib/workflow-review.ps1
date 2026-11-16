. (Join-Path $PSScriptRoot 'install-report.ps1')
. (Join-Path $PSScriptRoot 'stage-result.ps1')
function Show-WorkflowStatus {
    param([string]$Session)
    Invoke-DotfilesRequest workflow-status @{session=$Session;style='windows'}
}
