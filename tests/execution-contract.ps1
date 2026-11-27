$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $Repo 'lib/workflow.ps1')
. (Join-Path $PSScriptRoot 'fixtures/install/commands/setup.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
foreach ($Line in Get-Content (Join-Path $Repo 'tests/fixtures/execution/outcomes.tsv')) {
    if ($Line.StartsWith('#')) { continue }
    $Fields = $Line.Split("`t")
    $Result = Get-ExecutionResult ([int]$Fields[0]) ($Fields[1] -eq '1')
    Assert ($Result.Status -ceq $Fields[2] -and $Result.Reason -ceq $Fields[3]) "Wrong outcome: $Line"
}
foreach ($Line in Get-Content (Join-Path $Repo 'tests/fixtures/execution/probes.tsv')) {
    if ($Line.StartsWith('#')) { continue }
    $Fields = $Line.Split("`t"); $State = $Fields[0]
    if ($State -eq '<empty>') { $State = '' }
    $Failed = $false
    try { $Result = Get-InstallProbeResult $State } catch { $Failed = $true }
    if ($Fields[1] -eq 'invalid') { Assert $Failed "Accepted probe: $State" }
    else { Assert (-not $Failed -and $Result.Action -ceq $Fields[1] -and $Result.Reason -ceq $Fields[2]) "Wrong probe: $State" }
}
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-execution-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$PreviousPath = $env:PATH; $PreviousState = $env:DOTFILES_TEST_PACKAGE_STATE
try {
    Invoke-InstallCommand @{ DryRun = $true } 'missing-contract-command' @()
    $Failed = $false
    try { Invoke-InstallCommand @{ DryRun = $false } 'missing-contract-command' @() }
    catch { $Failed = (Get-ExecutionExceptionCode $_.Exception) -eq 127 }
    Assert $Failed 'Missing command must have a structured exit code'
    $Context = @{ SessionId = 'test'; SessionPath = Join-Path $Temp 'session'; ProfileName = 'test'; DryRun = $false; ResultsPath = Join-Path $Temp 'result.json'; StagePlan = @(
        @{ Id = 'packages'; Enabled = $true; Action = 'packages' },
        @{ Id = 'configuration'; Enabled = $true; Action = 'configuration' }
    ) }
    $Fixture = New-FakeWinGet $Temp
    $Context.RepoRoot = Join-Path $Temp 'repo'
    $Items = Join-Path $Context.RepoRoot 'software/items'
    $null = New-Item -ItemType Directory $Items
    Copy-Item (Join-Path $PSScriptRoot 'fixtures/install/windows/tool.conf') $Items
    $Context.Profile = @{install='all'}
    $Context.InstallContext = @{DryRun=$false;ProgramFiles=$Temp;VsInstallerRoot=$Temp}
    '130' | Set-Content (Join-Path $Fixture.State 'install-exit')
    'tool' | Set-Content (Join-Path $Fixture.State 'report-id')
    (Join-Path $Context.SessionPath 'packages.tsv') | Set-Content (Join-Path $Fixture.State 'report-source')
    (Join-Path $Temp 'running-install.tsv') | Set-Content (Join-Path $Fixture.State 'install-snapshot')
    $Failed = $false
    try { Invoke-WorkflowStages $Context } catch { $Failed = $true; Write-Host $_.Exception.Message }
    Assert ((Get-Content (Join-Path $Temp 'running-install.tsv') -Raw) -match 'tool\|running\|') 'Missing durable item start'
    [object[]]$Rows = Get-Content $Context.ResultsPath -Raw | ConvertFrom-Json
    $ExpectedFields = @(Get-Content (Join-Path $Repo 'workflow/schema/report-fields.tsv') | Where-Object { -not $_.StartsWith('#') } | ForEach-Object { $_.Split("`t")[0] } | Sort-Object)
    $ActualFields = @($Rows[0].PSObject.Properties.Name | Sort-Object)
    Assert (($ExpectedFields -join '|') -ceq ($ActualFields -join '|')) 'Report field contract differs'
    Assert ($Failed -and $Rows[0].status -eq 'interrupted' -and $Rows[0].exit_code -eq 130) 'Missing interrupted outcome'
    $StatusText = (& (Join-Path $Repo 'workflow/status.ps1') -Session $Context.SessionPath) -join "`n"
    Assert ($StatusText -match '-Resume ') 'Missing session resume entry'
    Remove-Item (Join-Path $Context.SessionPath 'request.tsv')
    $LegacyText = (& (Join-Path $Repo 'workflow/status.ps1') -Session $Context.SessionPath) -join "`n"
    Assert ($LegacyText -match 'Legacy session has no saved selection') 'Missing legacy read-only guidance'
    Assert ($Rows[1].status -eq 'blocked' -and $Rows[1].retry_stage -eq 'packages' -and $Rows[1].schema_version -eq 1) 'Missing retry/version contract'
} finally {
    $env:PATH = $PreviousPath; $env:DOTFILES_TEST_PACKAGE_STATE = $PreviousState
    Remove-FakeWinGetLinks $Fixture
    Remove-Item $Temp -Recurse -Force
}
Write-Host 'Execution outcomes, probes, command prerequisites and interrupted-session contracts passed.'
