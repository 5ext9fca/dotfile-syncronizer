[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Snapshot, [switch]$DryRun, [switch]$PlanOnly, [switch]$DetachHardlink)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/python.ps1')
Initialize-DotfilesPython
$Arguments = @('-m', 'dotfiles_viewer', 'snapshot', 'apply', '--snapshot', $Snapshot)
if ($DryRun -or $PlanOnly) { $Arguments += '--dry-run' }
if ($DetachHardlink) { $Arguments += '--detach-hardlink' }
& $env:DOTFILES_PYTHON @Arguments
exit $LASTEXITCODE
