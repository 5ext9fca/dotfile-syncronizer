$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/install-items.ps1')
. (Join-Path $PSScriptRoot 'fixtures/install/commands/setup.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('discovery-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$PreviousPath = $env:PATH; $PreviousState = $env:DOTFILES_TEST_PACKAGE_STATE
try {
    $Fixture = New-FakeWinGet $Temp
    $Context = @{ ProgramFiles = $Temp }
    $Fixtures = Join-Path $PSScriptRoot 'fixtures/install/discovery'
    $Plan = @(Get-InstallPlan $Fixtures windows $false $false $true $Context)
    Assert ($Plan[0].method -eq 'winget' -and $Plan[0].action -eq 'install') 'Wrong preferred method or absent state'
    $null = New-Item -ItemType Directory (Join-Path $Temp 'Tool/tool.exe') -Force
    Assert (-not (Get-InstallDiscoveryState $Plan[0] $Context)) 'Directory mistaken for a file'
    Remove-Item (Join-Path $Temp 'Tool/tool.exe')
    $null = New-Item -ItemType File (Join-Path $Temp 'Tool/tool.exe')
    Assert ((Get-InstallDiscoveryState $Plan[0] $Context) -eq 'discovered:winget') 'File was not recognized'
    Assert ((Get-WindowsResumeItem $Plan[0] $Context).action -eq 'skip') 'Resume ignored current files'
    Remove-Item (Join-Path $Temp 'Tool/tool.exe')
    $null = New-Item -ItemType Directory (Join-Path $Temp 'Manual Tool')
    Assert (-not (Get-InstallDiscoveryState $Plan[0] $Context)) 'Partial alternate installation accepted'
    $null = New-Item -ItemType File (Join-Path $Temp 'Manual Tool/tool.exe')
    $Fresh = @(Get-InstallPlan $Fixtures windows $false $false $true $Context)[0]
    Assert ($Fresh.action -eq 'skip' -and $Fresh.state -eq 'discovered:manual') 'Alternate installation not recognized'
    Assert (@(Get-InstallPlan $Fixtures windows $false $false $false $Context)[0].action -eq 'install') 'Offline plan inspected host'
    Remove-Item (Join-Path $Temp 'Manual Tool/tool.exe')
    Assert ((Get-WindowsResumeItem $Fresh $Context).action -eq 'install') 'Historical presence overrode removed files'
    $Roundtrip = @(ConvertFrom-InstallPlanText ((ConvertTo-InstallPlanText $Plan -Envelope) -join "`n"))
    Assert ($Roundtrip[0].discovery -eq $Plan[0].discovery) 'Discovery contract lost paths'
    Assert (-not (Test-Path (Join-Path $Fixture.State 'commands'))) 'Discovery queried an application or package inventory'
    . (Join-Path $PSScriptRoot '../lib/install-command.ps1')
    Set-Content (Join-Path $Fixture.State 'report-id') 'tool'
    $Report = Join-Path $Fixture.State results; $Calls = Join-Path $Fixture.State installs
    Invoke-InstallPlan $Plan @{ DryRun=$false } $Report
    Assert ((Get-Content $Calls) -eq 'Vendor.Tool') 'Wrong installation recipe selected'
    Clear-Content $Calls
    Set-Content (Join-Path $Fixture.State 'install-exit') 23
    $Code = 0
    try { Invoke-InstallPlan $Plan @{ DryRun=$false } $Report } catch { $Code = Get-ExecutionExceptionCode $_.Exception }
    Assert ($Code -eq 23 -and (Get-Content $Calls) -eq 'Vendor.Tool') 'Preferred recipe failure caused fallback'
    'PowerShell application discovery and current-state rechecks passed.'
} finally {
    $env:PATH = $PreviousPath; $env:DOTFILES_TEST_PACKAGE_STATE = $PreviousState
    Remove-FakeWinGetLinks $Fixture
    Remove-Item -LiteralPath $Temp -Recurse -Force
}
