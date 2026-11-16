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
Initialize-DotfilesPython
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
# Resolve caller-relative paths in this PowerShell host before launching Python.
$Context = @{
    style='windows'; native_shell=(Get-Process -Id $PID).Path; kind='configuration'; repo=$RepoRoot;
    dry=[bool]$DryRun; plan_only=[bool]$PlanOnly; selection=@($Components);
    restore=$(if ($Restore) { [IO.Path]::GetFullPath($Restore) } else { '' });
    roots=@{ home=$env:USERPROFILE; app_data=$env:APPDATA; local_app_data=$env:LOCALAPPDATA };
    config=''; backup=''; results=''; metadata=''
}
# Restore ignores deployment destinations; PlanOnly ignores report outputs.
if (-not $Restore) {
    $Context.config = if ($env:LOCALAPPDATA) { [IO.Path]::GetFullPath($env:LOCALAPPDATA) } else { '' }
    $Context.backup = if ($env:DOTFILES_BACKUP_DIR) { [IO.Path]::GetFullPath($env:DOTFILES_BACKUP_DIR) } else { Join-Path $HOME '.dotfiles-backups' }
    if (-not $PlanOnly) {
        if ($ResultsPath) { $Context.results = [IO.Path]::GetFullPath($ResultsPath) }
        if ($StageResultPath) { $Context.metadata = [IO.Path]::GetFullPath($StageResultPath) }
    }
}
Invoke-DeploymentLocked ([bool]($DryRun -or $PlanOnly)) {
    Invoke-DotfilesRequest apply-entry-native $Context -Stream
}
