$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $Repo 'lib/install-items.ps1')
. (Join-Path $Repo 'lib/apply-items.ps1')
. (Join-Path $Repo 'lib/workflow.ps1')
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-workflow-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function New-TestWorkflowContext {
    param([string]$SessionId, [string[]]$Selected, [bool]$Dry = $false, [bool]$Report = $true)
    $Plan = @(Get-WorkflowStagePlan windows @{} '' '')
    foreach ($Stage in $Plan) { $Stage.Enabled = $Stage.Id -cin $Selected; $Stage.Reason = if ($Stage.Enabled) { '' } else { 'selection' } }
    @{
        SessionId = $SessionId; SessionPath = Join-Path $Temp $SessionId; ProfileName = 'windows'
        StagePlan = $Plan; DryRun = $Dry; ResultsPath = $(if ($Report) { Join-Path $Temp "$SessionId.json" } else { '' })
    }
}
try {
    foreach ($Name in @('linux', 'wsl', 'macos', 'windows')) {
        $Profile = Read-WorkflowProfile (Join-Path $Repo "workflow/profiles/$Name.conf")
        Assert ($Profile.install -eq 'none') 'Default profile must select no installation items'
    }
    $Profile = Read-WorkflowProfile (Join-Path $Repo 'workflow/profiles/windows.conf')
    $Plan = @(Get-InstallPlan -Directory (Join-Path $Repo 'install/items') -Inspect $false)
    $Components = @(Get-WorkflowComponents $Profile $Plan @(Read-ApplyItems (Join-Path $Repo 'apply/items')))
    Assert ($Components.Count -eq 1 -and $Components[0] -eq 'windows-terminal') 'Wrong Windows component association'
    $Profile.install = 'leaf'
    $Selected = @(Select-WorkflowInstallPlan $Profile @(@{ id = 'base' }, @{ id = 'leaf'; depends_on = 'base' }, @{ id = 'other' }))
    Assert (($Selected.id -join ',') -eq 'base,leaf') 'Selected installation must include dependencies and preserve order'
    $Threw = $false
    try { Get-WorkflowStages -OnlyStage packages -FromStage configuration } catch { $Threw = $true }
    Assert $Threw 'Conflicting stage selectors accepted'
    Assert ((Get-WorkflowStages -FromStage configuration) -join ',' -eq 'configuration,wsl') 'Retry stage order changed'

    # Exercise failure across the real native adapter boundary. Invalid apply
    # declarations fail before any target mutation, and block the WSL stage.
    $FailureContext = New-TestWorkflowContext failure @('configuration', 'wsl')
    $FailureContext.RepoRoot = Join-Path $Temp 'missing-repository'
    $FailureContext.ConfigRoot = Join-Path $Temp 'failed-config'
    $FailureContext.Components = @('windows-terminal')
    $Threw = $false
    try { Invoke-WorkflowStages -Context $FailureContext } catch { $Threw = $true }
    Assert $Threw 'Stage failure did not propagate'
    $Results = @(Get-Content (Join-Path $Temp 'failure.json') -Raw | ConvertFrom-Json)
    Assert (($Results.status -join ',') -eq 'skipped,skipped,failed,blocked') 'Incorrect failure summary'
    Assert ((Get-Item $Results[2].log).Length -gt 0) 'Stage failure log was not captured'
    Assert (-not (Test-Path $FailureContext.ConfigRoot)) 'Failed preflight mutated configuration'

    # Successful no-op stages must still have valid logs and summaries.
    $Noop = New-TestWorkflowContext noop @('git')
    $Noop.ProgramFiles = $Temp
    $Noop.DryRun = $true
    $Noop.GitSettings = @()
    Invoke-WorkflowStages -Context $Noop
    $Results = @(Get-Content (Join-Path $Temp 'noop.json') -Raw | ConvertFrom-Json)
    Assert ($Results[1].status -eq 'planned' -and (Test-Path $Results[1].log)) 'No-op stage has no log or failed'

    # Exercise the real entry point in an isolated configuration-only dry run.
    $Saved = @{}
    foreach ($Name in @('LOCALAPPDATA', 'DOTFILES_BACKUP_DIR', 'ProgramFiles', 'ProgramFiles(x86)')) { $Saved[$Name] = [Environment]::GetEnvironmentVariable($Name) }
    try {
        $env:LOCALAPPDATA = Join-Path $Temp 'local-app-data'
        $env:DOTFILES_BACKUP_DIR = Join-Path $Temp 'entry-backups'
        $env:ProgramFiles = Join-Path $Temp 'program-files'
        [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', (Join-Path $Temp 'program-files-x86'))
        & (Join-Path $Repo 'install/windows.ps1') -OnlyStage configuration -DryRun -ResultsPath (Join-Path $Temp 'entry.json') -SessionId entry
        $Results = @(Get-Content (Join-Path $Temp 'entry.json') -Raw | ConvertFrom-Json)
        Assert ($Results[2].status -eq 'planned') 'Real entry did not plan configuration'
        Assert (-not (Test-Path $env:LOCALAPPDATA)) 'Entry dry run created a configuration directory'
        Assert (Test-Path $Results[2].report) 'Real entry lost its apply report'
        $PlanText = (@(& (Join-Path $Repo 'install/windows.ps1') -OnlyStage configuration -PlanOnly -SessionId entry-plan) -join "`n") -split '\r?\n'
        $Copies = @($PlanText | Where-Object { $_ -match '^windows-terminal\|copy\|' })
        Assert ($Copies.Count -eq 1 -and $Copies[0].Split('|')[6] -match ':f:') 'Plan-only lost the source-state projection'
        Assert (-not (Test-Path (Join-Path $env:DOTFILES_BACKUP_DIR 'workflow-entry-plan'))) 'Plan-only created a persistent session'
    } finally { foreach ($Name in $Saved.Keys) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name]) } }

    # Full stage prerequisite ordering and WSL failure blocking are covered by
    # the core preflight tests; this suite exercises the native public entry
    # above and the actual Windows/WSL argument boundary below.

    # Mock WSL only: each probe and argument is verified without launching a distro.
    $script:WslCalls = @(); $script:WslFail = $false
    $HostPython = $env:DOTFILES_PYTHON
    function wsl.exe {
        Assert (-not $env:DOTFILES_PYTHON) 'Host Python leaked to WSL'
        $script:WslCalls += ,@($args)
        $global:LASTEXITCODE = 0
        if ($script:WslFail) { $global:LASTEXITCODE = 9; return }
        if ($args[0] -eq '--list') { '  FedoraLinux-44 Running 2' }
        elseif ($args -contains 'printenv') { '/home/test' }
        elseif ($args -contains '--plan') { 'Stage packages:'; 'Stage configuration:' }
    }
    function Invoke-ManagedCommand {
        param($Policy, $Command, $Arguments, $TimeoutSeconds, [switch]$Stream)
        Assert ($Command -eq 'wsl.exe') 'Unexpected native command in WSL tests'
        if ($Policy -eq 'probe') { Assert ($TimeoutSeconds -eq 30) 'WSL probe must have a timeout' }
        $Output = @(& wsl.exe @Arguments)
        @{ ExitCode = $global:LASTEXITCODE; Stdout = $Output -join "`n"; Stderr = '' }
    }
    $Wsl = Get-WorkflowWslPlan -RepoRoot "\\wsl.localhost\FedoraLinux-44\home\test\quote' path" -Distribution FedoraLinux-44 -SessionId shared -RecordReports $true -NoChinaMirrors $true
    Assert ($env:DOTFILES_PYTHON -eq $HostPython) 'Host runtime not restored after WSL query'
    Assert ($Wsl.Arguments -contains 'shared') 'Session identity not forwarded to WSL'
    Assert ($Wsl.Arguments -contains '--no-china-mirrors') 'Mirror flag not forwarded'
    Assert ($Wsl.Arguments -contains '/home/test/.dotfiles-workflow-shared.tsv') 'Nested dry-run report not requested'
    Assert ($Wsl.Arguments -contains "/home/test/quote' path/install/linux.sh") 'WSL path was not passed literally'
    Assert (-not (@($script:WslCalls | Where-Object { $_ -contains '-lc' }).Count)) 'WSL paths interpolated into shell source'
    Assert ($Wsl.HostReport -eq '\\wsl.localhost\FedoraLinux-44\home\test\.dotfiles-workflow-shared.tsv') 'Missing structured child report location'
    $WslResult = Join-Path $Temp 'wsl.result'
    Initialize-StageResult $WslResult wsl ''
    $WslContext = @{ RepoRoot = '\\wsl.localhost\FedoraLinux-44\home\test\repo'; Profile = @{ wsl = 'FedoraLinux-44'; wsl_profile = 'wsl-full' }; NoChinaMirrors = $false; SessionId = 'typed-child'; DryRun = $false; ResultsPath = '' }
    & (Get-WindowsWorkflowActions).wsl $WslContext (Join-Path $Temp 'wsl.tsv') $WslResult
    $Artifacts = @(Read-StageResult $WslResult | Where-Object key -eq 'child_report')
    Assert ($Artifacts.Count -eq 1 -and $Artifacts[0].value -like '*typed-child.tsv') 'Child report was not passed through structured stage results'
    # Arbitrary existing WSL2 distributions and guest profiles are data.
    function wsl.exe {
        Assert (-not $env:DOTFILES_PYTHON) 'Host Python leaked to WSL'
        $script:WslCalls += ,@($args)
        $global:LASTEXITCODE = 0
        if ($args[0] -eq '--list') { '  CustomLinux Running 2' }
        elseif ($args -contains '--plan') { 'Stage configuration:' }
    }
    $Custom = Get-WorkflowWslPlan -RepoRoot '\\wsl.localhost\CustomLinux\home\test\repo' -Distribution CustomLinux -GuestProfile guest-config -SessionId custom -NoChinaMirrors $false
    Assert ($Custom.Arguments -contains 'guest-config' -and $Custom.Arguments -contains '--china-mirrors') 'Custom guest profile or mirror policy not forwarded'
    Assert (-not (@($script:WslCalls | Where-Object { $_ -contains '/etc/fedora-release' }).Count)) 'Fedora-specific inspection remains'
    $Threw = $false
    try { Get-WorkflowWslPlan -RepoRoot 'C:\repo' -Distribution CustomLinux -SessionId wrong } catch { $Threw = $true }
    Assert $Threw 'Wrong checkout accepted'
    function wsl.exe { $global:LASTEXITCODE = 0; if ($args[0] -eq '--list') { '  CustomLinux Running 1' } }
    $Threw = $false
    try { Get-WorkflowWslPlan -RepoRoot '\\wsl.localhost\CustomLinux\home\test\repo' -Distribution CustomLinux -SessionId version } catch { $Threw = $true }
    Assert $Threw 'WSL1 accepted'
    $script:WslFail = $true; $Threw = $false
    try { Get-WorkflowWslPlan -RepoRoot '\\wsl.localhost\FedoraLinux-44\home\test\repo' -Distribution FedoraLinux-44 -SessionId failure } catch { $Threw = $true }
    Assert $Threw 'Failed WSL inspection accepted'
    Write-Host 'Windows workflow profile, stage failure/retry, reporting and WSL preflight tests passed.'
} finally { Remove-Item -LiteralPath $Temp -Recurse -Force }
