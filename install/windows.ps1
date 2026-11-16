[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoChinaMirrors,
    [switch]$ChinaMirrors,
    [string]$Profile,
    [switch]$PlanOnly,
    [string]$ResultsPath,
    [string]$OnlyStage,
    [string]$FromStage,
    [string]$Resume,
    [string]$SessionId = ([guid]::NewGuid().ToString('N'))
)
$ErrorActionPreference = 'Stop'
if ($PSBoundParameters.ContainsKey('Profile') -and $Profile -cnotmatch '^[a-z][a-z0-9-]*$') { throw 'Invalid profile name' }
if ($ChinaMirrors -and $NoChinaMirrors) { throw 'ChinaMirrors and NoChinaMirrors are mutually exclusive' }
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/workflow.ps1')
Initialize-DotfilesPython
$Options = @{
    RepoRoot = $RepoRoot; SessionId = $SessionId; DryRun = [bool]$DryRun; PlanOnly = [bool]$PlanOnly
    NoChinaMirrors = [bool]$NoChinaMirrors; ResultsPath = $ResultsPath; OnlyStage = $OnlyStage; FromStage = $FromStage
    ProfileName = $Profile; ProfileExplicit = $PSBoundParameters.ContainsKey('Profile')
    Resume = $Resume; MirrorsExplicit = ($PSBoundParameters.ContainsKey('NoChinaMirrors') -or $PSBoundParameters.ContainsKey('ChinaMirrors'))
    ConfigRoot = $env:LOCALAPPDATA
    BackupRoot = $(if ($env:DOTFILES_BACKUP_DIR) { $env:DOTFILES_BACKUP_DIR } else { Join-Path $HOME '.dotfiles-backups' })
    ProgramFiles = $env:ProgramFiles
    VsInstallerRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer'
    GitConfigPaths = @(Get-WorkflowGitConfigPaths)
}
Invoke-WindowsWorkflow $Options
