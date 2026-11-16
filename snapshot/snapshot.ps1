[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)][ValidateSet('create','inspect','restore')][string]$Action,
    [string]$Profile,
    [string]$Catalog,
    [switch]$DetachHardlink,
    [string[]]$Software = @(),
    [string]$Output,
    [string]$Snapshot,
    [switch]$DryRun,
    [switch]$PlanOnly,
    [switch]$ConfigurationOnly
)
$ErrorActionPreference = 'Stop'
if ($Catalog) { $env:DOTFILES_CATALOG = [IO.Path]::GetFullPath($Catalog) }
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/python.ps1')
. (Join-Path $RepoRoot 'lib/deployment-lock.ps1')
if ($Action -eq 'create') {
    if (-not $Output -or $Snapshot -or $ConfigurationOnly -or ([bool]$Profile -eq [bool]$Software.Count)) { throw 'create requires Output and exactly one of Profile or Software' }
} elseif (-not $Snapshot -or $Output -or $Profile -or $Software.Count) { throw 'inspect/restore requires Snapshot and cannot select software' }
Initialize-DotfilesPython
$Context = @{
    detach_hardlink=[bool]$DetachHardlink; action=$Action; native_shell=(Get-Process -Id $PID).Path; dry=[bool]($DryRun -or $PlanOnly);
    profile=$Profile; software=@($Software); configuration_only=[bool]$ConfigurationOnly;
    output=$(if ($Output) { [IO.Path]::GetFullPath($Output) } else { '' });
    snapshot=$(if ($Snapshot) { [IO.Path]::GetFullPath($Snapshot) } else { '' })
}
Invoke-DeploymentLocked ([bool]($DryRun -or $PlanOnly -or $Action -eq 'inspect')) {
    Invoke-DotfilesRequest snapshot-native $Context -Stream
}
