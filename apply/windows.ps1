[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$PlanOnly,
    [string]$ResultsPath,
    [string]$StageResultPath,
    [string]$Restore,
    [string]$Profile,
    [string[]]$Components = @()
)
$ErrorActionPreference = 'Stop'
if ($PSBoundParameters.ContainsKey('Profile') -and $Profile -cnotmatch '^[a-z][a-z0-9-]*$') { throw 'Invalid profile name' }
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/apply-items.ps1')
. (Join-Path $RepoRoot 'lib/workflow-profile.ps1')
if ($Restore) {
    if ($Components.Count -or $Profile) { throw 'Restore cannot select components' }
    Restore-ApplyJournal $Restore ([bool]($DryRun -or $PlanOnly))
    return
}
if ($Components.Count -and $Profile) { throw 'Components and Profile are mutually exclusive' }
if (-not $Components.Count) {
    if (-not $Profile) { $Profile = 'windows' }
    $Declaration = Read-WorkflowProfile (Get-WorkflowProfilePath $RepoRoot $Profile)
    $Components = @($Declaration.components.Split(' ') | ForEach-Object { $_.Split(':')[0] })
}
$Roots = @{ home = $env:USERPROFILE; app_data = $env:APPDATA; local_app_data = $env:LOCALAPPDATA }
$BackupRoot = Resolve-ApplyRoot $(if ($env:DOTFILES_BACKUP_DIR) { $env:DOTFILES_BACKUP_DIR } else { Join-Path $HOME '.dotfiles-backups' })
$Session = Join-Path $BackupRoot ('apply-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
$Plan = @(Get-ApplyPlan -RepoRoot $RepoRoot -Items (Join-Path $PSScriptRoot 'items') -Roots $Roots -Session $Session -Components $Components)
if ($PlanOnly) { ConvertTo-ApplyPlanText $Plan; return }
Invoke-ApplyPlan -Plan $Plan -Session $Session -DryRun ([bool]$DryRun) -ResultsPath $ResultsPath -StageResultPath $StageResultPath
Write-Host 'Windows configuration applied successfully.'
