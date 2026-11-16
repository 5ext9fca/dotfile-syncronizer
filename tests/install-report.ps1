$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/workflow.ps1')
. (Join-Path $PSScriptRoot 'fixtures/install/commands/setup.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('reports-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$PreviousPath = $env:PATH; $PreviousState = $env:DOTFILES_TEST_PACKAGE_STATE
try {
    $Fixtures = Join-Path $PSScriptRoot 'fixtures/install-reports'
    foreach ($Line in Get-Content -LiteralPath (Join-Path $Fixtures 'cases.tsv')) {
        if ($Line.StartsWith('#')) { continue }
        $Name, $Expected = ($Line -split '\|', 2)
        $Failed = $false; $Actual = @()
        try { $Actual = @(Read-InstallResult ([IO.File]::ReadAllText((Join-Path $Fixtures "$Name.txt")))) } catch { $Failed = $true }
        if ($Expected -eq 'error') { Assert ($Failed -and $Actual.Count -eq 0) "Accepted invalid report: $Name" }
        else {
            Assert (-not $Failed -and $Actual.Count -eq 1) "Rejected valid report: $Name"
            $Row = (Get-DataContractFields install-result | ForEach-Object { [string]$Actual[0][$_] }) -join '|'
            Assert ($Row -ceq $Expected) "Report adapter mismatch: $Name"
        }
    }
    $Root = Join-Path $Temp ('space;' + [char]0x4e2d + [char]0x6587)
    $null = New-Item -ItemType Directory (Join-Path $Root 'Manual Tool') -Force
    $File = Join-Path $Root 'Manual Tool/tool.exe'; $null = New-Item -ItemType File $File
    $Context = @{ ProgramFiles=$Root; DryRun=$false }
    $Offline = @(Get-InstallPlan (Join-Path $PSScriptRoot 'fixtures/install/discovery') windows $false $false $false $Context)[0]
    Assert (-not $Offline.detected_method -and -not $Offline.detected_paths -and $Offline.decision_reason -eq 'offline-preferred-method') 'Offline plan published observations'
    $Plan = @(Get-InstallPlan (Join-Path $PSScriptRoot 'fixtures/install/discovery') windows $false $false $true $Context)
    Assert ($Plan[0].detected_method -eq 'manual') 'Alternate installation evidence missing'
    $Paths = ConvertFrom-Json -InputObject $Plan[0].detected_paths
    Assert ($Paths.Count -eq 2 -and $Paths[0] -eq $File -and $Paths[1] -eq (Join-Path $Root 'Manual Tool')) 'Wrong matched paths'
    $Report = Join-Path $Temp 'report.tsv'
    Invoke-InstallPlan $Plan $Context $Report
    $Result = @(Read-InstallResult (Get-Content $Report -Raw))[0]
    Assert ($Result.status -eq 'skipped' -and $Result.selected_method -eq 'winget' -and $Result.detected_method -eq 'manual' -and $Result.decision_reason -eq 'discovered-installation') 'Missing selection evidence in report'
    # Exercise the public status entry point without reading any log.
    $Session = Join-Path $Temp session; $null = New-Item -ItemType Directory $Session
    $Summary = @{ schema_version=1; session='test'; profile='windows'; stage='packages'; status='success'; exit_code=0; elapsed_seconds=0; log=''; report=$Report; reason=''; recovery_journal=''; child_report=''; retry_stage='' }
    Write-AtomicReport (Join-Path $Session workflow.json) (ConvertTo-Json -InputObject @($Summary))
    $Status = (& (Join-Path $PSScriptRoot '../workflow/status.ps1') -Session $Session) -join "`n"
    Assert ($Status.Contains('Item tool: skipped') -and $Status.Contains('Preferred method: winget') -and $Status.Contains('Matched method: manual') -and $Status.Contains($Plan[0].detected_paths)) 'Status omitted structured evidence'
    Copy-Item (Join-Path $Fixtures legacy.txt) $Report -Force
    $Status = (& (Join-Path $PSScriptRoot '../workflow/status.ps1') -Session $Session) -join "`n"
    Assert ($Status.Contains('Item tool: skipped (already-installed)') -and -not $Status.Contains('Matched method')) 'Historical status invented evidence'
    # The first matching method wins; never combine paths from different methods.
    $null = New-Item -ItemType Directory (Join-Path $Root Tool)
    $PreferredFile = Join-Path $Root 'Tool/tool.exe'; $null = New-Item -ItemType File $PreferredFile
    $Tie = @(Get-InstallPlan (Join-Path $PSScriptRoot 'fixtures/install/discovery') windows $false $false $true $Context)[0]
    [string[]]$TiePaths = ConvertFrom-Json -InputObject $Tie.detected_paths
    Assert ($Tie.detected_method -eq 'winget' -and $TiePaths.Count -eq 1 -and $TiePaths[0] -eq $PreferredFile) 'First match combined unrelated paths'
    Remove-Item $PreferredFile
    $OldPath = $env:PATH
    try {
        $First = Join-Path $Temp first; $Second = Join-Path $Temp second
        $null = New-Item -ItemType Directory $First, $Second
        $null = New-Item -ItemType File (Join-Path $First 'evidence-tool.exe'), (Join-Path $Second 'evidence-tool.exe')
        $env:PATH = @('', $First, $Second, $OldPath) -join [IO.Path]::PathSeparator
        $PathObservation = Get-InstallDiscoveryObservation @{ discovery='winget:file:path:evidence-tool.exe' } $Context
        Assert (([string[]](ConvertFrom-Json -InputObject $PathObservation.Paths))[0] -eq (Join-Path $First 'evidence-tool.exe')) 'PATH evidence did not record first nonempty match'
    } finally { $env:PATH = $OldPath }
    Remove-Item $File
    $Fresh = Get-WindowsResumeItem $Plan[0] $Context
    Assert (-not $Fresh.detected_method -and -not $Fresh.detected_paths -and $Fresh.decision_reason -eq 'no-discovery-match') 'Removed/partial files retained evidence'
    $Fixture = New-FakeWinGet $Temp
    Set-Content (Join-Path $Fixture.State 'report-source') $Report
    Set-Content (Join-Path $Fixture.State 'report-id') 'tool'
    Set-Content (Join-Path $Fixture.State 'install-snapshot') (Join-Path $Temp running.tsv)
    Set-Content (Join-Path $Fixture.State 'install-exit') 23
    $Later = $Plan[0].Clone(); $Later.id = 'later'; $Code = 0
    try { Invoke-InstallPlan @($Fresh, $Later) $Context $Report } catch { $Code = Get-ExecutionExceptionCode $_.Exception }
    Assert ($Code -eq 23) 'Wrong failure code'
    $Running = @(Read-InstallResult (Get-Content (Join-Path $Temp running.tsv) -Raw))[0]
    Assert ($Running.status -eq 'running' -and $Running.decision_reason -eq 'no-discovery-match') 'Running report omitted decision'
    $Rows = @(Read-InstallResult (Get-Content $Report -Raw))
    Assert ($Rows[0].reason -eq 'exit-23' -and $Rows[0].decision_reason -eq 'no-discovery-match') 'Failure erased original decision'
    Assert ($Rows[1].status -eq 'blocked' -and -not $Rows[1].detected_method -and -not $Rows[1].detected_paths -and -not $Rows[1].decision_reason) 'Blocked item published stale evidence'
    # Current environment exclusions must remain excluded during resume.
    function Get-WindowsItemState { throw 'Excluded item must not be inspected' }
    foreach ($Reason in @('environment-not-selected:wsl', 'provided-by-host:windows-docker-desktop')) {
        $Excluded = @{ reason=$Reason; action='skip'; method='winget' }
        Assert ((Get-WindowsResumeItem $Excluded $Context).reason -eq $Reason) 'Resume lost environment gate'
    }
    . (Join-Path $PSScriptRoot '../lib/install-state.ps1')
    Set-Content (Join-Path $Fixture.State 'probe-snapshot') (Join-Path $Temp checking.tsv)
    Set-Content (Join-Path $Fixture.State 'probe-exit') 42
    $ProbePlan = $Plan[0].Clone(); $ProbePlan.discovery = ''
    $Context.ResumeItems = $true; $Code = 0
    try { Invoke-InstallPlan @($ProbePlan) $Context $Report } catch { $Code = Get-ExecutionExceptionCode $_.Exception }
    Assert ($Code -eq 42) 'Wrong probe failure code'
    $Checking = @(Read-InstallResult (Get-Content (Join-Path $Temp checking.tsv) -Raw))[0]
    Assert ($Checking.reason -eq 'checking-current-state' -and -not $Checking.detected_method -and -not $Checking.decision_reason) 'Checking snapshot retained stale evidence'
    $Failed = @(Read-InstallResult (Get-Content $Report -Raw))[0]
    Assert ($Failed.id -eq 'tool' -and $Failed.reason -eq 'exit-42' -and -not $Failed.detected_method -and -not $Failed.detected_paths -and -not $Failed.decision_reason) 'Failed probe published stale evidence'
    Write-Host 'Installation evidence, report snapshots, historical readers and status explanation passed.'
} finally {
    $env:PATH = $PreviousPath; $env:DOTFILES_TEST_PACKAGE_STATE = $PreviousState
    Remove-FakeWinGetLinks $Fixture
    Remove-Item -LiteralPath $Temp -Recurse -Force
}
