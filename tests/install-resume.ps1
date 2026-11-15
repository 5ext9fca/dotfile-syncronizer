$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/workflow.ps1')
. (Join-Path $PSScriptRoot 'fixtures/install/commands/setup.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('install-resume-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$PreviousPath = $env:PATH; $PreviousState = $env:DOTFILES_TEST_PACKAGE_STATE
try {
    $Fixture = New-FakeWinGet $Temp; $State = $Fixture.State
    $Report = Join-Path $State 'results'; $Calls = Join-Path $State 'installs'
    $Plan = @('first','second','third') | ForEach-Object { @{schema_version=(Get-DataContractVersion install-plan); id=$_; method='winget'; packages=$_; source_repo='winget'; action='install'; reason='requested'; source_origin='config'} }
    $null = New-Item -ItemType File (Join-Path $State 'fail-second')
    $Code=0
    try { Invoke-InstallPlan $Plan @{DryRun=$false} $Report } catch { $Code=Get-ExecutionExceptionCode $_.Exception }
    Assert ($Code -eq 23 -and ((Get-Content $Calls) -join ',') -eq 'first,second') 'Initial failure gating incorrect'
    Remove-Item (Join-Path $State 'fail-second'); Clear-Content $Calls
    Invoke-InstallPlan $Plan @{DryRun=$false; ResumeItems=$true} $Report
    Assert (((Get-Content $Calls) -join ',') -eq 'second,third') 'Resume repeated installed item or lost order'
    Remove-Item (Join-Path $State 'installed-first'); Clear-Content $Calls
    Invoke-InstallPlan $Plan @{DryRun=$false; ResumeItems=$true} $Report
    Assert (((Get-Content $Calls) -join ',') -eq 'first') 'Historical success overrode current state'
    foreach ($Expected in @(124,42)) {
        Set-Content (Join-Path $State 'probe-exit') $Expected; Clear-Content $Calls
        $Code=0
        try { Invoke-InstallPlan $Plan @{DryRun=$false; ResumeItems=$true} $Report } catch { $Code=Get-ExecutionExceptionCode $_.Exception }
        Assert ($Code -eq $Expected -and -not (Get-Content $Calls)) 'Probe failure did not block installation'
    }
    Remove-Item (Join-Path $State 'probe-exit')
    # Successful inventory must contain the requested package identity.
    $Item = @{ id='absent'; method='winget'; packages='absent'; source_repo='winget' }
    Assert ((Get-WindowsResumeItem $Item @{}).action -eq 'install') 'Unrelated inventory treated as installed'
    # Normal reruns use current inventory too, including additions and removed evidence.
    Clear-Content $Calls
    $Normal = @($Plan | ForEach-Object { Get-InstallObservedItem $_ @{} normal })
    Invoke-InstallPlan $Normal @{DryRun=$false} $Report
    Assert (-not (Get-Content $Calls)) 'Normal run repeated installed packages'
    Remove-Item (Join-Path $State 'installed-first')
    $Normal = @($Plan | ForEach-Object { Get-InstallObservedItem $_ @{} normal })
    Invoke-InstallPlan $Normal @{DryRun=$false} $Report
    Assert (((Get-Content $Calls) -join ',') -eq 'first') 'Normal run ignored removed evidence'
    Assert ((Get-InstallObservedItem $Item @{} normal).action -eq 'install') 'New declaration was skipped'
    Set-Content (Join-Path $State 'probe-exit') 42
    $Code=0
    try { Get-InstallObservedItem $Item @{} normal } catch { $Code=Get-ExecutionExceptionCode $_.Exception }
    Assert ($Code -eq 42) 'Normal run swallowed discovery failure'
    Remove-Item (Join-Path $State 'probe-exit')
    # A closed PATH prevents discovery from falling through to the real host WinGet.
    Remove-Item (Join-Path $Fixture.Bin 'winget.exe')
    Assert (-not (Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue)) 'Host WinGet leaked into test'
    Assert ((Get-WindowsResumeItem $Plan[0] @{}).action -eq 'install') 'Missing command was treated as package evidence'
    'PowerShell real fake-command resume, failure gating and host isolation passed.'
} finally {
    $env:PATH = $PreviousPath; $env:DOTFILES_TEST_PACKAGE_STATE = $PreviousState
    if ($Fixture -and $env:OS -ne 'Windows_NT') {
        Get-ChildItem -LiteralPath $Fixture.Bin | Where-Object { $_.LinkType -eq 'SymbolicLink' } | ForEach-Object { [IO.File]::Delete($_.FullName) }
    }
    Remove-Item -LiteralPath $Temp -Recurse -Force
}
