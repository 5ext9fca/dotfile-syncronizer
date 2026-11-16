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
    Initialize-DotfilesPython
    Assert-ApplyPlan $Plan
    Invoke-DeploymentLocked $DryRun { Invoke-ApplyPlanUnlocked $Plan $Session $DryRun $ResultsPath $StageResultPath }
}
function Restore-ApplyJournal {
    param([string]$Journal, [bool]$DryRun)
    Initialize-DotfilesPython
    Invoke-DeploymentLocked $DryRun {
        $null = Invoke-DotfilesRequest apply-restore-native @{
            style='windows'; native_shell=(Get-Process -Id $PID).Path;
            journal=[IO.Path]::GetFullPath($Journal); dry=$DryRun
        } -Stream
    }
}

function Invoke-ApplyPlanUnlocked {
    param([object[]]$Plan, [string]$Session, [bool]$DryRun, [string]$ResultsPath, [string]$StageResultPath)
    $null = Invoke-DotfilesRequest apply-execute-native @{
        style='windows'; native_shell=(Get-Process -Id $PID).Path; records=@(ConvertTo-ApplyRecords $Plan);
        session=[IO.Path]::GetFullPath($Session); dry=$DryRun;
        results=$(if ($ResultsPath) { [IO.Path]::GetFullPath($ResultsPath) } else { '' });
        metadata=$(if ($StageResultPath) { [IO.Path]::GetFullPath($StageResultPath) } else { '' })
    } -Stream
}
