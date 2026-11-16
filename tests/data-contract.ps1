$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $Repo 'lib/workflow.ps1')
. (Join-Path $PSScriptRoot 'fixtures/install/commands/setup.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
foreach ($Line in Get-Content (Join-Path $Repo 'tests/fixtures/contracts/cases.tsv')) {
    $Name, $Status = $Line.Split("`t"); $Failed = $false; $Rows = @()
    try { $Rows = @(Read-DataContract git-result (Get-Content (Join-Path $Repo "tests/fixtures/contracts/$Name.txt") -Raw)) } catch { $Failed = $true }
    if ($Status -eq 'valid') { Assert (-not $Failed -and $Rows.Count -eq 1 -and $Rows[0].key -ceq 'core.editor' -and $Rows[0].status -ceq 'success') "Wrong contract: $Name" }
    else { Assert ($Failed -and $Rows.Count -eq 0) "Accepted invalid/partial contract: $Name" }
}
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-data-contract-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$PreviousPath = $env:PATH; $PreviousState = $env:DOTFILES_TEST_PACKAGE_STATE
try {
    $Plan = @(Get-InstallPlan (Join-Path $PSScriptRoot 'fixtures/install/windows') -Inspect $false)
    $Later = $Plan[0].Clone(); $Later.id = 'later'; $Later.schema_version = 9
    $Plan += $Later
    $Fixture = New-FakeWinGet $Temp
    $Failed = $false
    try { Invoke-InstallPlan $Plan @{ DryRun = $false } } catch { $Failed = $true }
    Assert ($Failed -and -not (Test-Path (Join-Path $Fixture.State 'installs'))) 'Unknown version reached native execution'
    # Restore PATH before the independent filesystem tests.
    $env:PATH = $PreviousPath

    $Failed = $false
    try { Invoke-ApplyPlan @(@{ schema_version = 9; Action = 'mkdir'; Target = Join-Path $Temp 'target' }) (Join-Path $Temp 'session') $false } catch { $Failed = $true }
    Assert ($Failed -and -not (Test-Path (Join-Path $Temp 'session'))) 'Unknown apply version created a session'
    $Path = Join-Path $Temp 'stage.result'
    Initialize-StageResult $Path configuration ''
    Set-StageResultValue $Path recovery_journal 'path with, comma/journal' -Append
    Complete-StageResult $Path 23 $false (Join-Path $Temp 'missing-report')
    $Rows = @(Read-StageResult $Path)
    Assert (($Rows | Where-Object key -eq 'recovery_journal').value -ceq 'path with, comma/journal') 'Structured artifact was split'
    Assert (($Rows | Where-Object key -eq 'status').value -eq 'failed') 'Missing structured failure'
    $Context = @{ SessionId = 'corrupt'; SessionPath = Join-Path $Temp 'workflow'; ProfileName = 'test'; DryRun = $false; ResultsPath = Join-Path $Temp 'workflow.json'; StagePlan = @(
        @{ Id = 'packages'; Enabled = $true; Action = 'packages' },
        @{ Id = 'configuration'; Enabled = $true; Action = 'configuration' }
    ) }
    $env:PATH = $Fixture.Bin
    $Context.RepoRoot = Join-Path $Temp 'repo'
    $Items = Join-Path $Context.RepoRoot 'install/items'
    $null = New-Item -ItemType Directory $Items
    Copy-Item (Join-Path $PSScriptRoot 'fixtures/install/windows/tool.conf') $Items
    $Context.Profile = @{install='all'}
    $Context.InstallContext = @{DryRun=$false;ProgramFiles=$Temp;VsInstallerRoot=$Temp}
    'tool' | Set-Content (Join-Path $Fixture.State 'report-id')
    (Join-Path $Context.SessionPath 'packages.tsv') | Set-Content (Join-Path $Fixture.State 'report-source')
    (Join-Path $Context.SessionPath 'packages.result') | Set-Content (Join-Path $Fixture.State 'corrupt-stage')
    $Failed = $false
    try { Invoke-WorkflowStages $Context } catch { $Failed = $true; Write-Host $_.Exception.Message }
    $Summary = @(Get-Content $Context.ResultsPath -Raw | ConvertFrom-Json)
    Assert ($Failed -and $Summary[0].exit_code -eq 65 -and $Summary[0].status -eq 'failed') 'Corrupt metadata accepted'
    Assert ($Summary[1].status -eq 'blocked') 'Corrupt metadata did not block dependent stages'

} finally {
    $env:PATH = $PreviousPath; $env:DOTFILES_TEST_PACKAGE_STATE = $PreviousState
    Remove-FakeWinGetLinks $Fixture
    Remove-Item $Temp -Recurse -Force
}
Write-Host 'Versioned contracts, pre-execution rejection and structured artifact tests passed.'
