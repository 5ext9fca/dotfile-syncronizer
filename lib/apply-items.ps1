. (Join-Path $PSScriptRoot 'stage-result.ps1')
. (Join-Path $PSScriptRoot 'atomic-report.ps1')
# Public apply API: declarations -> filesystem inspection -> plan -> transaction -> restore.
. (Join-Path $PSScriptRoot 'apply-schema.ps1')
. (Join-Path $PSScriptRoot 'apply-fs.ps1')
. (Join-Path $PSScriptRoot 'apply-plan.ps1')
. (Join-Path $PSScriptRoot '../apply/handlers/files.ps1')
. (Join-Path $PSScriptRoot 'apply-restore.ps1')

. (Join-Path $PSScriptRoot 'deployment-lock.ps1')
function Invoke-ApplyPlan {
    param([object[]]$Plan, [string]$Session, [bool]$DryRun, [string]$ResultsPath, [string]$StageResultPath)
    Assert-ApplyPlan $Plan
    Invoke-DeploymentLocked $DryRun { Invoke-ApplyPlanUnlocked $Plan $Session $DryRun $ResultsPath $StageResultPath }
}
function Restore-ApplyJournal {
    param([string]$Journal, [bool]$DryRun)
    Invoke-DeploymentLocked $DryRun { Restore-ApplyJournalUnlocked $Journal $DryRun }
}
