. (Join-Path $PSScriptRoot 'python.ps1')
function Show-InstallPlanExplanation {
    param([object[]]$Plan, [string]$Platform, [string]$Selection = 'all', [string]$Directory)
    Invoke-DotfilesRequest install-explain @{ records=@($Plan);platform=$Platform;selection=$Selection;directory=$Directory }
}
function Show-ApplyPlanExplanation {
    param([object[]]$Plan)
    Invoke-DotfilesRequest apply-explain @{ records=@(ConvertTo-ApplyRecords $Plan) }
}
