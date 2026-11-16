$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $Repo 'lib/apply-items.ps1')
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-apply-entry-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $Work
$Saved = @{}
foreach ($Name in @('LOCALAPPDATA', 'DOTFILES_BACKUP_DIR', 'DOTFILES_DEPLOYMENT_LOCK', 'DOTFILES_DEPLOYMENT_TOKEN')) {
    $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name)
}
try {
    $env:LOCALAPPDATA = Join-Path $Work 'config space'
    $env:DOTFILES_BACKUP_DIR = Join-Path $Work 'backups'
    $env:DOTFILES_DEPLOYMENT_LOCK = Join-Path $Work 'lock'
    $env:DOTFILES_DEPLOYMENT_TOKEN = $null
    $Entry = Join-Path $Repo 'apply/windows.ps1'
    $IgnoredPath = "invalid$([char]0)"
    $Text = (@(& $Entry -PlanOnly -ResultsPath $IgnoredPath -StageResultPath $IgnoredPath) -join "`n")
    $Plan = @(ConvertFrom-ApplyPlanText $Text)
    if (@($Plan | Where-Object Action -eq 'copy').Count -ne 1) { throw 'Standalone plan lost its file operation' }
    & $Entry -DryRun
    if ((Test-Path $env:LOCALAPPDATA) -or (Test-Path $env:DOTFILES_BACKUP_DIR)) { throw 'Standalone preview mutated target/session directories' }
    $Metadata = Join-Path $Work 'stage.tsv'
    & $Entry -ResultsPath (Join-Path $Work 'report.tsv') -StageResultPath $Metadata
    $Target = @($Plan | Where-Object Action -eq 'copy')[0].Target
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { throw 'Standalone entry did not deploy the file' }
    $Journal = @(Read-StageResult $Metadata | Where-Object key -eq 'recovery_journal')[0].value
    if (-not $Journal) { throw 'Standalone entry lost its recovery journal reference' }
    & $Entry -Restore $Journal -PlanOnly -ResultsPath $IgnoredPath -StageResultPath $IgnoredPath
    if (-not (Test-Path -LiteralPath $Target)) { throw 'Restore preview changed the target' }
    & $Entry -Restore $Journal
    if ((Test-Path -LiteralPath $Target) -or (Test-Path $env:DOTFILES_DEPLOYMENT_LOCK)) { throw 'Standalone restoration or lease release failed' }
} finally {
    foreach ($Name in $Saved.Keys) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name]) }
    Remove-Item -LiteralPath $Work -Recurse -Force
}
Write-Host 'Standalone Windows apply plan, preview, deployment and recovery passed.'
