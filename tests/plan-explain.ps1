$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/workflow.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Plan = @(Get-InstallPlan (Join-Path $PSScriptRoot 'fixtures/install/dependencies') linux.apt -Inspect $false)
$Text = @(Show-InstallPlanExplanation $Plan linux.apt leaf) -join "`n"
Assert ($Text.Contains('selected-by=dependency') -and $Text.Contains('depends-on:') -and $Text.Contains('method=apt')) 'Missing selection explanation'
$Plan = @(Get-InstallPlan (Join-Path $Repo 'install/items') linux.apt -Wsl $true -Inspect $false)
$Text = @(Show-InstallPlanExplanation $Plan linux.apt all (Join-Path $Repo 'install/items')) -join "`n"
Assert ($Text.Contains('provided-by-host:windows-docker-desktop') -and $Text.Contains('msvc: excluded (platform-not-configured)') -and $Text.Contains('Source: pypi-index (mirror)')) 'Missing exclusion/source explanation'
$Text = @(Show-ApplyPlanExplanation @(@{Component='terminal';Action='copy';Target='/target';Source='/source';Backup='/backup';Reason='replace'}, @{Component='terminal';Action='skip';Target='/same';Reason='unchanged'})) -join "`n"
Assert ($Text.Contains('copy /target (replace)') -and $Text.Contains('Existing target backup: /backup') -and $Text.Contains('skip /same (unchanged)')) 'Missing configuration effects'
'PowerShell plan explanation tests passed.'
