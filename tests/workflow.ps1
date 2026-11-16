$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $Repo 'lib/workflow.ps1')
foreach ($Name in @('linux','macos','windows','wsl')) {
    $Profile = Read-WorkflowProfile (Join-Path $Repo "workflow/profiles/$Name.conf")
    if ($Profile.install -eq 'none' -or $Profile.components -ne 'none' -or $Profile.wsl -ne 'none' -or $Profile.shell -ne 'none') { throw 'Invalid unified profile behavior' }
}
$Profile = Read-WorkflowProfile (Join-Path $Repo 'workflow/profiles/windows-full.conf')
$Stages = @(Get-WorkflowStagePlan windows $Profile '' '')
if (($Stages.Id -join ',') -ne 'packages') { throw 'Installer must only run packages' }
$Profile.install = 'leaf'
$Selected = @(Select-WorkflowInstallPlan $Profile @(@{id='base'}, @{id='leaf';depends_on='base'}, @{id='other'}))
if (($Selected.id -join ',') -ne 'base,leaf') { throw 'Dependencies not selected' }
$Failed = $false
try { Get-WorkflowStages -OnlyStage packages -FromStage configuration } catch { $Failed = $true }
if (-not $Failed) { throw 'Conflicting selection accepted' }
Write-Host 'Unified Windows workflow selection passed; snapshot integration is in test_snapshot.py.'
