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
        Assert ($Profile.install -eq 'all') 'Default profile must select all platform items'
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

    $script:Calls = @()
    $Actions = @{
        packages = { param($Context, $Report); if ($Context.SessionId -ne 'failure') { throw 'Missing explicit stage context' }; $script:Calls += 'packages'; 'id|status' | Set-Content $Report; Write-Host 'native package log'; throw 'package failed' }
        git = { $script:Calls += 'git' }
        configuration = { $script:Calls += 'configuration' }
        wsl = { $script:Calls += 'wsl' }
    }
    $Threw = $false
    try { Invoke-WorkflowStages -Context (New-TestWorkflowContext failure @('packages', 'git', 'configuration', 'wsl')) -Actions $Actions } catch { $Threw = $true }
    Assert $Threw 'Stage failure did not propagate'
    Assert (($script:Calls -join ',') -eq 'packages') 'Downstream stage executed after failure'
    $Results = @(Get-Content (Join-Path $Temp 'failure.json') -Raw | ConvertFrom-Json)
    Assert (($Results.status -join ',') -eq 'failed,blocked,blocked,blocked') 'Incorrect failure summary'
    Assert ((Get-Content $Results[0].log -Raw) -match 'native package log') 'Stage log was not captured'
    Assert (Test-Path $Results[0].report) 'Missing item report link'

    $script:Calls = @()
    $Actions.configuration = { param($Context, $Report, $StageResultPath); Set-StageResultValue $StageResultPath recovery_journal 'test-journal' -Append; $script:Calls += 'configuration'; Write-Host 'Recovery journal: forged-log-path'; 'component report' | Set-Content $Report }
    Invoke-WorkflowStages -Context (New-TestWorkflowContext retry @('configuration')) -Actions $Actions
    $Results = @(Get-Content (Join-Path $Temp 'retry.json') -Raw | ConvertFrom-Json)
    Assert (($script:Calls -join ',') -eq 'configuration') 'Single-stage retry executed other stages'
    Assert ($Results[2].recovery_journal -eq 'test-journal') 'Recovery journal missing from summary'
    Invoke-WorkflowStages -Context (New-TestWorkflowContext dry @('configuration') $true $false) -Actions $Actions
    Assert (-not (Test-Path (Join-Path $Temp 'dry'))) 'Dry run created persistent session'

    # Future Git configuration files are protected even before they exist.
    $Threw = $false
    try { Assert-WorkflowOutput (Join-Path $Temp 'future-git-config') @((Join-Path $Temp 'future-git-config')) } catch { $Threw = $true }
    Assert $Threw 'Report could overwrite a Git configuration created later in the workflow'

    # Successful no-op stages must still have valid logs and summaries.
    Invoke-WorkflowStages -Context (New-TestWorkflowContext noop @('git')) -Actions @{ git = {} }
    $Results = @(Get-Content (Join-Path $Temp 'noop.json') -Raw | ConvertFrom-Json)
    Assert ($Results[1].status -eq 'success' -and (Test-Path $Results[1].log)) 'No-op stage has no log or failed'

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
    } finally { foreach ($Name in $Saved.Keys) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name]) } }

    # The full orchestration must finish every preflight before creating a
    # session, deploying files or invoking a package manager.
    $OriginalWslPlan = ${function:Get-WindowsWorkflowWslPlan}
    $OriginalGitPath = ${function:Get-WindowsWorkflowGitPath}
    $script:HostMutations = @()
    function winget.exe { $script:HostMutations += 'winget'; throw 'Unexpected host mutation' }
    function Get-WindowsWorkflowGitPath { param($Context); Join-Path $Context.ProgramFiles 'missing-git.exe' }
    function Get-WindowsWorkflowWslPlan { param($Context); throw 'injected WSL preflight failure' }
    $Options = @{
        RepoRoot = $Repo; SessionId = 'preflight'; DryRun = $false; PlanOnly = $false; NoChinaMirrors = $false
        ResultsPath = ''; OnlyStage = ''; FromStage = ''; ConfigRoot = Join-Path $Temp 'preflight-config'
        BackupRoot = Join-Path $Temp 'preflight-backups'; ProgramFiles = Join-Path $Temp 'program-files'
        VsInstallerRoot = Join-Path $Temp 'vs-installer'; GitConfigPaths = @((Join-Path $Temp 'git-config'))
    }
    try {
        $Threw = $false
        try { Invoke-WindowsWorkflow $Options } catch { $Threw = $_.Exception.Message -eq 'injected WSL preflight failure' }
        Assert $Threw 'Full workflow did not reach or propagate WSL preflight failure'
        Assert ($script:HostMutations.Count -eq 0) 'Windows mutated before WSL preflight completed'
        Assert (-not (Test-Path $Options.ConfigRoot) -and -not (Test-Path $Options.BackupRoot)) 'Preflight failure created deployment/session directories'
        function Get-WindowsWorkflowWslPlan { param($Context); @{ Text = @('Nested Linux plan'); Arguments = @() } }
        $Options.PlanOnly = $true
        $Text = @(Invoke-WindowsWorkflow $Options) -join "`n"
        foreach ($Stage in @('packages', 'git', 'configuration', 'wsl')) { Assert ($Text.Contains("Stage ${Stage}:")) "Full plan omitted $Stage" }
        Assert ($Text.Contains('Nested Linux plan') -and $script:HostMutations.Count -eq 0) 'Full plan failed to include nested inspection or mutated the host'
        Assert (-not (Test-Path $Options.BackupRoot)) 'Plan-only created a session'
    } finally {
        Set-Item Function:Get-WindowsWorkflowWslPlan $OriginalWslPlan
        Set-Item Function:Get-WindowsWorkflowGitPath $OriginalGitPath
        Remove-Item Function:winget.exe
    }

    # Mock WSL only: each probe and argument is verified without launching a distro.
    $script:WslCalls = @(); $script:WslFail = $false
    function wsl.exe {
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
    Assert ($Wsl.Arguments -contains 'shared') 'Session identity not forwarded to WSL'
    Assert ($Wsl.Arguments -contains '--no-china-mirrors') 'Mirror flag not forwarded'
    Assert ($Wsl.Arguments -contains '/home/test/.dotfiles-workflow-shared.tsv') 'Nested dry-run report not requested'
    Assert ($Wsl.Arguments -contains "/home/test/quote' path/install/linux.sh") 'WSL path was not passed literally'
    Assert (-not (@($script:WslCalls | Where-Object { $_ -contains '-lc' }).Count)) 'WSL paths interpolated into shell source'
    Assert ($Wsl.HostReport -eq '\\wsl.localhost\FedoraLinux-44\home\test\.dotfiles-workflow-shared.tsv') 'Missing structured child report location'
    $WslResult = Join-Path $Temp 'wsl.result'
    Initialize-StageResult $WslResult wsl ''
    $WslContext = @{ RepoRoot = '\\wsl.localhost\FedoraLinux-44\home\test\repo'; Profile = @{ wsl = 'FedoraLinux-44' }; NoChinaMirrors = $false; SessionId = 'typed-child'; DryRun = $false; ResultsPath = '' }
    & (Get-WindowsWorkflowActions).wsl $WslContext (Join-Path $Temp 'wsl.tsv') $WslResult
    $Artifacts = @(Read-StageResult $WslResult | Where-Object key -eq 'child_report')
    Assert ($Artifacts.Count -eq 1 -and $Artifacts[0].value -like '*typed-child.tsv') 'Child report was not passed through structured stage results'
    $script:WslFail = $true; $Threw = $false
    try { Get-WorkflowWslPlan -RepoRoot '\\wsl.localhost\FedoraLinux-44\home\test\repo' -Distribution FedoraLinux-44 -SessionId failure } catch { $Threw = $true }
    Assert $Threw 'Failed WSL inspection accepted'
    Write-Host 'Windows workflow profile, stage failure/retry, reporting and WSL preflight tests passed.'
} finally { Remove-Item -LiteralPath $Temp -Recurse -Force }
