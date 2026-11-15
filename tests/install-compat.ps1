$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/install-items.ps1')
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('compat-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$SavedPath = $env:PATH
$env:PATH = $Temp + [IO.Path]::PathSeparator + $env:PATH
try {
    $Command = Join-Path $Temp 'legacy-tool.ps1'
    Set-Content -LiteralPath $Command -Value "throw 'Presence detection must not execute this command'"
    @"
[windows]
order=1
method=winget
packages=Vendor.Tool
source_kind=winget
source_repo=winget
scope=desktop
check=legacy-tool.ps1
"@ | Set-Content -LiteralPath (Join-Path $Temp 'tool.conf')
    $Item = @(Get-InstallPlan $Temp windows $false $false $true @{})[0]
    if ($Item.action -ne 'skip' -or $Item.environments -ne 'native' -or $Item.methods -ne 'winget' -or $Item.preferred_method -ne 'winget') { throw 'Legacy normalization failed' }
    if ($Item.ContainsKey('scope') -or $Item.ContainsKey('check') -or -not $Item.probe_command) { throw 'Legacy fields leaked into the core model' }
    if (@(Get-InstallPlan $Temp windows $false $true $true @{})[0].reason -ne 'environment-not-selected:wsl') { throw 'Environment gate mismatch' }
    Remove-Item -LiteralPath $Command
    if (@(Get-InstallPlan $Temp windows $false $false $true @{})[0].action -ne 'install') { throw 'Removed command is still present' }
    Write-Host 'Legacy declarations normalize once and retain command/environment behavior.'
} finally { $env:PATH = $SavedPath; Remove-Item -LiteralPath $Temp -Recurse -Force }
