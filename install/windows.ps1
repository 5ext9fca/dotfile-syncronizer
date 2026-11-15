[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NoChinaMirrors,
    [switch]$PlanOnly,
    [string]$ResultsPath,
    [string]$OnlyStage,
    [string]$FromStage,
    [string]$Resume,
    [string]$SessionId = ([guid]::NewGuid().ToString('N'))
)
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/workflow.ps1')
$Options = @{
    RepoRoot = $RepoRoot; SessionId = $SessionId; DryRun = [bool]$DryRun; PlanOnly = [bool]$PlanOnly
    NoChinaMirrors = [bool]$NoChinaMirrors; ResultsPath = $ResultsPath; OnlyStage = $OnlyStage; FromStage = $FromStage
    Resume = $Resume; MirrorsExplicit = $PSBoundParameters.ContainsKey('NoChinaMirrors')
    ConfigRoot = $env:LOCALAPPDATA
    BackupRoot = $(if ($env:DOTFILES_BACKUP_DIR) { $env:DOTFILES_BACKUP_DIR } else { Join-Path $HOME '.dotfiles-backups' })
    ProgramFiles = $env:ProgramFiles
    VsInstallerRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer'
    GitConfigPaths = @(Get-WorkflowGitConfigPaths)
}
Invoke-WindowsWorkflow $Options
