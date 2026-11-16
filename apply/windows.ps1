[CmdletBinding()]
param([string]$Snapshot, [string]$Restore, [switch]$DryRun, [switch]$PlanOnly)
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($Restore -and -not $Snapshot) {
    . (Join-Path $RepoRoot 'lib/apply-items.ps1')
    Initialize-DotfilesPython
    Restore-ApplyJournal ([IO.Path]::GetFullPath($Restore)) ([bool]($DryRun -or $PlanOnly))
} elseif ($Snapshot -and -not $Restore) {
    & (Join-Path $RepoRoot 'snapshot/snapshot.ps1') restore -Snapshot $Snapshot -ConfigurationOnly -DryRun:($DryRun -or $PlanOnly)
} else { throw 'Specify -Snapshot FILE to apply captured configuration, or -Restore JOURNAL for guarded recovery.' }
