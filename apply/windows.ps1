[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$PlanOnly,
    [string]$ResultsPath,
    [string]$StageResultPath,
    [string]$Restore,
    [string[]]$Components = @()
)
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/apply-items.ps1')
if ($Restore) {
    if ($Components.Count) { throw 'Restore cannot select components' }
    Restore-ApplyJournal $Restore ([bool]($DryRun -or $PlanOnly))
    return
}
$TargetRoot = Resolve-ApplyRoot $env:LOCALAPPDATA
$BackupRoot = Resolve-ApplyRoot $(if ($env:DOTFILES_BACKUP_DIR) { $env:DOTFILES_BACKUP_DIR } else { Join-Path $HOME '.dotfiles-backups' })
$Session = Join-Path $BackupRoot ('apply-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
$Plan = @(Get-ApplyPlan -RepoRoot $RepoRoot -Items (Join-Path $PSScriptRoot 'items') -TargetRoot $TargetRoot -Session $Session -Components $Components)
if ($PlanOnly) { ConvertTo-ApplyPlanText $Plan; return }
Invoke-ApplyPlan -Plan $Plan -Session $Session -DryRun ([bool]$DryRun) -ResultsPath $ResultsPath -StageResultPath $StageResultPath
Write-Host 'Windows configuration applied successfully.'
