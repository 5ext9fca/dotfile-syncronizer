$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/workflow.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action) { $Failed = $false; try { & $Action } catch { $Failed = $true }; Assert $Failed 'Invalid resume accepted' }
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('resume-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
try {
    $Context = @{ ProfileName = 'windows'; NoChinaMirrors = $true; DryRun = $false; Resume = ''; OnlyStage = ''; FromStage = ''; StagePlan = @(Get-WorkflowStagePlan windows @{} configuration '') }
    Save-WorkflowRequest $Context $Temp
    Assert ((Read-WorkflowRequest $Temp).selected_stages -eq 'configuration') 'Selection not saved'
    $Row = [ordered]@{ schema_version=1; session='old'; profile='windows'; stage='configuration'; status='failed'; exit_code=23; elapsed_seconds=0; log=''; report=''; recovery_journal=''; reason='command-failed'; child_report=''; retry_stage='configuration' }
    Write-AtomicReport (Join-Path $Temp 'workflow.json') (ConvertTo-Json -InputObject @($Row))
    $Metadata = Join-Path $Temp 'configuration.result'
    Initialize-StageResult $Metadata configuration ''
    Set-StageResultValue $Metadata recovery_journal (Join-Path $Temp 'journal,one.tsv') -Append
    Complete-StageResult $Metadata 23 $false ''
    $Context.Resume = $Temp; $Context.NoChinaMirrors = $false
    Initialize-WorkflowResume $Context
    Assert $Context.NoChinaMirrors 'Mirror mode not restored'
    $Context.StagePlan = @(Get-WorkflowStagePlan windows @{} '' '')
    Select-WorkflowResumeStages $Context
    Assert ((@($Context.StagePlan | Where-Object Enabled).Id -join ',') -eq 'configuration') 'Single-stage resume expanded selection'
    $Text = @(Show-WorkflowStatus $Temp) -join "`n"
    Assert ($Text.Contains('exit=23') -and $Text.Contains('journal,one.tsv') -and $Text.Contains('-Resume')) 'Missing failure context'
    # Failed/deferred dry runs must not recommend a rejected -Resume command.
    $Context.DryRun = $true; Save-WorkflowRequest $Context $Temp
    foreach ($Code in @(23,75,130)) {
        Complete-StageResult $Metadata $Code $true ''
        $Text = @(Show-WorkflowStatus $Temp) -join "`n"
        Assert ($Text.Contains('original command with -DryRun') -and $Text.Contains('same stage selection and mirror options') -and -not $Text.Contains('-Resume')) 'Dry-run status recommended resume'
    }
    Reject { Initialize-WorkflowResume $Context }
    $Context.DryRun = $false; Save-WorkflowRequest $Context $Temp
    Complete-StageResult $Metadata 23 $false ''
    # Exercise the actual Windows entry in dry-run mode with isolated targets.
    $OldEnvironment = @{}
    foreach ($Name in @('LOCALAPPDATA','ProgramFiles','ProgramFiles(x86)','DOTFILES_BACKUP_DIR')) { $OldEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name) }
    try {
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', (Join-Path $Temp 'config'))
        [Environment]::SetEnvironmentVariable('ProgramFiles', (Join-Path $Temp 'programs'))
        [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', (Join-Path $Temp 'programs-x86'))
        [Environment]::SetEnvironmentVariable('DOTFILES_BACKUP_DIR', (Join-Path $Temp 'backups'))
        $NewReport = Join-Path $Temp 'resume-preview.json'
        & (Join-Path $PSScriptRoot '../install/windows.ps1') -Resume $Temp -DryRun -ResultsPath $NewReport -SessionId resume-cli
        $NewSession = Join-Path $Temp 'backups/workflow-resume-cli'
        $Saved = Read-WorkflowRequest $NewSession
        Assert ($Saved.resume_parent -eq $Temp -and $Saved.selected_stages -eq 'configuration' -and $Saved.china_mirrors -eq '0') 'Windows CLI lost resume context'
        $Rows = @(Read-WorkflowReview $NewSession)
        Assert (@($Rows | Where-Object { $_.status -eq 'planned' }).Count -eq 1) 'Windows CLI expanded resume selection'
        # Windows may create Microsoft/Windows/Caches under redirected LOCALAPPDATA.
        # The deployment-owned Packages tree must remain absent.
        Assert (-not (Test-Path (Join-Path $Temp 'config/Packages'))) 'Windows dry-run deployed configuration'
    } finally {
        foreach ($Name in $OldEnvironment.Keys) { [Environment]::SetEnvironmentVariable($Name, $OldEnvironment[$Name]) }
    }
    $Context.OnlyStage = 'packages'; Reject { Initialize-WorkflowResume $Context }; $Context.OnlyStage = ''
    $Context.MirrorsExplicit = $true; Reject { Initialize-WorkflowResume $Context }; $Context.MirrorsExplicit = $false
    Complete-StageResult $Metadata 0 $false ''
    Reject { Initialize-WorkflowResume $Context }
    $Context.Resume = ''; $Context.StagePlan = @(Get-WorkflowStagePlan windows @{} '' ''); Save-WorkflowRequest $Context $Temp
    $Row.stage = 'packages'; $Row.status = 'success'; $Row.exit_code = 0
    Write-AtomicReport (Join-Path $Temp 'workflow.json') (ConvertTo-Json -InputObject @($Row))
    $Context.Resume = $Temp; Initialize-WorkflowResume $Context
    Assert (($Context.ResumeStages -join ',') -eq 'git,configuration,wsl') 'Missing rows were not resumed'
    $Context.DryRun = $true; Save-WorkflowRequest $Context $Temp; Reject { Initialize-WorkflowResume $Context }
    $Context.DryRun = $false; Save-WorkflowRequest $Context $Temp
    $Row.status = 'failed'; $Row.exit_code = 23; $Row.report = Join-Path $Temp 'packages.tsv'
    Write-DataContractRows install-result @('docker|failed|1|exit-23||||') $Row.report
    Write-AtomicReport (Join-Path $Temp 'workflow.json') (ConvertTo-Json -InputObject @($Row))
    $Text = @(Show-WorkflowStatus $Temp) -join "`n"
    Assert ($Text.Contains('Item docker: failed (exit-23)') -and -not $Text.Contains('restore')) 'Incorrect package failure advice'
    'corrupt' | Set-Content (Join-Path $Temp 'packages.result')
    Reject { Initialize-WorkflowResume $Context }
    'PowerShell workflow resume and failure summary tests passed.'
} finally { Remove-Item -LiteralPath $Temp -Recurse -Force }
