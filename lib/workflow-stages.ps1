# Compatibility objects for the platform workflow adapter.
. (Join-Path $PSScriptRoot 'python.ps1')
function Get-WorkflowStagePlan {
    param([string]$Platform, [hashtable]$Profile, [string]$OnlyStage, [string]$FromStage, [bool]$Mirrors = $true,
        [string]$Registry = (Join-Path $PSScriptRoot '../workflow/schema/stages.tsv'))
    $Text = (@($Profile.Keys | ForEach-Object { "$_=$($Profile[$_])" }) -join "`n")
    Invoke-DotfilesRule stage-plan @{platform=$Platform;profile=$Text;only=$OnlyStage;'from-stage'=$FromStage;mirrors=[int]$Mirrors;registry=$Registry}
}
function ConvertTo-WorkflowStagePlanText {
    param([object[]]$Plan)
    foreach ($Stage in $Plan) { "$($Stage.Id)|$([int]$Stage.Enabled)|$($Stage.Reason)|$($Stage.Preflight)|$($Stage.Action)" }
}
