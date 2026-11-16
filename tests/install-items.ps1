$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/install-items.ps1')
$FixtureRoot = Join-Path $PSScriptRoot 'fixtures/install'
. (Join-Path $FixtureRoot 'materialize.ps1')
. (Join-Path $FixtureRoot 'commands/setup.ps1')
$TestTemp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $TestTemp | Out-Null
$PreviousPath = $env:PATH; $PreviousState = $env:DOTFILES_TEST_PACKAGE_STATE
function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
}
try {
    $Count = 0
    foreach ($Line in Get-Content -LiteralPath (Join-Path $FixtureRoot 'cases.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Name, $Platform, $Mirrors, $Wsl, $Outcome = $Line.Split("`t")
        $Directory = New-InstallFixture $FixtureRoot $Name (Join-Path $TestTemp fixtures)
        $Failed = $false
        try {
            $Plan = @(Get-InstallPlan -Directory $Directory -Platform $Platform -Mirrors ($Mirrors -eq '1') -Wsl ($Wsl -eq '1') -Inspect $false)
            $Actual = @(ConvertTo-InstallPlanText -Plan $Plan)
        } catch { $Failed = $true; $ParseError = $_ }
        if ($Outcome -eq 'error') { Assert-True $Failed "Accepted invalid fixture: $Name" }
        else {
            if ($Failed) { throw "Rejected fixture ${Name}: $ParseError" }
            $Expected = @(Get-Content -LiteralPath (Join-Path $FixtureRoot "$Name/expected.plan"))
            Assert-True (($Actual -join "`n") -ceq ($Expected -join "`n")) "Plan mismatch: $Name"
        }
        $Count++
    }
    foreach ($Platform in @('linux.apt', 'linux.dnf', 'linux.pacman', 'macos', 'windows')) {
        $Plan = @(Get-InstallPlan -Directory (Join-Path $RepoRoot 'software/items') -Platform $Platform -Inspect $false)
        Assert-True ($Plan.Count -gt 0) "Empty repository plan: $Platform"
    }
    # Freeze a presence decision into a plan, then change the probe. Execution
    # must not call it again or install the previously detected item.
    $Fixture = New-FakeWinGet $TestTemp
    $null = New-Item -ItemType File (Join-Path $Fixture.State 'installed-Vendor.Tool')
    $Plan = @(Get-InstallPlan -Directory (Join-Path $FixtureRoot 'windows') -Inspect $true)
    Remove-Item (Join-Path $Fixture.State 'installed-Vendor.Tool')
    Clear-Content (Join-Path $Fixture.State 'commands')
    $Results = Join-Path $TestTemp 'skipped.txt'
    Set-Content (Join-Path $Fixture.State 'report-source') $Results
    Set-Content (Join-Path $Fixture.State 'report-id') 'tool'
    Invoke-InstallPlan -Plan $Plan -Context @{ DryRun = $false } -ResultsPath $Results
    Assert-True (-not (Get-Content (Join-Path $Fixture.State 'commands'))) 'Execution repeated a frozen presence probe'
    Assert-True ([bool](Select-String -LiteralPath $Results -Pattern '^tool\|skipped\|')) 'Missing skip result'

    # Exercise the actual MSVC/Git presence logic with a read-only probe adapter.
    . (Join-Path $RepoRoot 'lib/install-state.ps1')
    New-Item -ItemType File -Path (Join-Path $TestTemp 'vswhere.exe') | Out-Null
    $ProbeContext = @{ ProgramFiles = $TestTemp; VsInstallerRoot = $TestTemp }
    $MsvcProbe = @{ id = 'msvc'; method = 'msvc'; components = 'Test.Component' }
    function Invoke-InstallProbe { param($Command, $Arguments); return 'C:/Existing VS' }
    Assert-True ((Get-WindowsItemState -Item $MsvcProbe -Context $ProbeContext) -eq 'present') 'Installed MSVC was not detected'
    function Invoke-InstallProbe {
        param($Command, $Arguments)
        if ('-requires' -notin $Arguments) { return 'C:/Build Tools' }
    }
    Assert-True ((Get-WindowsItemState -Item $MsvcProbe -Context $ProbeContext) -eq 'modify:C:/Build Tools') 'Existing Build Tools workload was not selected'
    function Invoke-InstallProbe { param($Command, $Arguments) }
    Assert-True ((Get-WindowsItemState -Item $MsvcProbe -Context $ProbeContext) -eq '') 'Missing MSVC should request a fresh installation'
    function Invoke-InstallProbe { throw 'Deliberate probe failure' }
    $Failed = $false
    try { Get-WindowsItemState -Item $MsvcProbe -Context $ProbeContext } catch { $Failed = $true }
    Assert-True $Failed 'A failed probe was treated as an absent installation'
    New-Item -ItemType Directory -Path (Join-Path $TestTemp 'Git/cmd') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $TestTemp 'Git/cmd/git.exe') | Out-Null
    $Git = @(Read-InstallItems (Join-Path $RepoRoot 'software/items') windows | Where-Object { $_.id -eq 'git' })[0]
    Assert-True ((Get-WindowsItemState -Item $Git -Context $ProbeContext) -like 'discovered:*') 'Declared Git discovery path was ignored'

    # Actual WinGet/MSVC handlers with a recording command adapter, no host writes.
    . (Join-Path $RepoRoot 'install/handlers/windows.ps1')
    $script:Calls = @()
    function Invoke-InstallCommand {
        param($Context, $Command, $Arguments, $SuccessCodes, $Method, $Operation)
        $script:Calls += @{ Command = $Command; Arguments = $Arguments; SuccessCodes = $SuccessCodes; Method = $Method; Operation = $Operation }
    }
    $Plan = @(Get-InstallPlan -Directory (Join-Path $FixtureRoot 'windows') -Inspect $false)
    Install-WinGetItem -Item $Plan[0] -Context @{ DryRun = $true }
    Assert-True ($script:Calls[0].Command -eq 'winget.exe') 'Wrong WinGet command'
    Assert-True (($script:Calls[0].Arguments -join '|') -eq 'install|--id|Vendor.Tool|--exact|--source|winget|--accept-package-agreements|--accept-source-agreements') 'Wrong WinGet arguments'
    $Msvc = @{ state = 'modify:C:/Build Tools'; workload = 'Test.Workload' }
    Install-MsvcItem -Item $Msvc -Context @{ DryRun = $true; VsInstallerRoot = $TestTemp }
    Assert-True ($script:Calls[1].Arguments[2] -eq 'C:/Build Tools') 'MSVC path argument split incorrectly'
    Assert-True ($script:Calls[1].Method -eq 'msvc' -and $script:Calls[1].Operation -eq 'modify' -and 3010 -in (Get-InstallExecutionPolicy msvc modify).SuccessCodes) 'MSVC policy not selected'

    # Fail-fast results cover all items, including those blocked after the failure.
    . (Join-Path $RepoRoot 'lib/install-command.ps1')
    Remove-Item (Join-Path $Fixture.State 'report-id')
    Set-Content (Join-Path $Fixture.State 'install-exit') 23
    $Plan = @(@{ schema_version = (Get-DataContractVersion install-plan); id = 'first'; method = 'winget'; packages='first'; source_repo='winget'; action = 'install'; reason = 'requested' },
              @{ schema_version = (Get-DataContractVersion install-plan); id = 'second'; method = 'winget'; packages='second'; source_repo='winget'; action = 'install'; reason = 'requested' })
    $Results = Join-Path $TestTemp 'failure.txt'; $Failed = $false
    Set-Content (Join-Path $Fixture.State 'report-source') $Results
    try { Invoke-InstallPlan -Plan $Plan -Context @{ DryRun = $false } -ResultsPath $Results } catch { $Failed = $true }
    Assert-True $Failed 'Execution failure was swallowed'
    Assert-True ([bool](Select-String -LiteralPath $Results -Pattern '^first\|failed\|')) 'Missing failure result'
    Assert-True ([bool](Select-String -LiteralPath $Results -Pattern '^second\|blocked\|')) 'Missing blocked result'
    Write-Host "Install item PowerShell tests passed ($Count shared cases plus execution checks)."
} finally {
    $env:PATH = $PreviousPath; $env:DOTFILES_TEST_PACKAGE_STATE = $PreviousState
    Remove-FakeWinGetLinks $Fixture
    Remove-Item -LiteralPath $TestTemp -Recurse -Force
}
