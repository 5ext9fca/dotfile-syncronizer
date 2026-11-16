$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/workflow.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action) { $Failed = $false; try { & $Action } catch { $Failed = $true }; Assert $Failed 'Invalid resume accepted' }
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('resume-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$StatusEntry = Join-Path $PSScriptRoot '../workflow/status.ps1'
$InstallEntry = Join-Path $PSScriptRoot '../install/windows.ps1'
try {
    Write-DataContractRows workflow-request @('windows|windows|0|configuration||0') (Join-Path $Temp 'request.tsv')
    $Row = [ordered]@{ schema_version=1; session='old'; profile='windows'; stage='configuration'; status='failed'; exit_code=23; elapsed_seconds=0; log=''; report=''; recovery_journal=''; reason='command-failed'; child_report=''; retry_stage='configuration' }
    Write-AtomicReport (Join-Path $Temp 'workflow.json') (ConvertTo-Json -InputObject @($Row))
    $Metadata = Join-Path $Temp 'configuration.result'
    Initialize-StageResult $Metadata configuration ''
    Set-StageResultValue $Metadata recovery_journal (Join-Path $Temp 'journal,one.tsv') -Append
    Complete-StageResult $Metadata 23 $false ''
    $Text = @(& $StatusEntry -Session $Temp) -join "`n"
    Assert ($Text.Contains('exit=23') -and $Text.Contains('journal,one.tsv') -and $Text.Contains('-Resume')) 'Missing failure context'
    $OldEnvironment = @{}
    foreach ($Name in @('LOCALAPPDATA','ProgramFiles','ProgramFiles(x86)','DOTFILES_BACKUP_DIR')) { $OldEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name) }
    try {
        [Environment]::SetEnvironmentVariable('LOCALAPPDATA', (Join-Path $Temp 'config'))
        [Environment]::SetEnvironmentVariable('ProgramFiles', (Join-Path $Temp 'programs'))
        [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', (Join-Path $Temp 'programs-x86'))
        [Environment]::SetEnvironmentVariable('DOTFILES_BACKUP_DIR', (Join-Path $Temp 'backups'))
        $NewReport = Join-Path $Temp 'resume-preview.json'
        & $InstallEntry -Resume $Temp -DryRun -ResultsPath $NewReport -SessionId resume-cli
        $NewSession = Join-Path $Temp 'backups/workflow-resume-cli'
        $Saved = @(Read-DataContract workflow-request ([IO.File]::ReadAllText((Join-Path $NewSession 'request.tsv'))))[0]
        Assert ($Saved.resume_parent -eq $Temp -and $Saved.selected_stages -eq 'configuration' -and $Saved.china_mirrors -eq '0') 'Windows CLI lost resume context'
        $Rows = @(Get-Content -LiteralPath $NewReport -Raw | ConvertFrom-Json)
        Assert (@($Rows | Where-Object { $_.status -eq 'planned' }).Count -eq 1) 'Windows CLI expanded resume selection'
        Assert (-not (Test-Path (Join-Path $Temp 'config/Packages'))) 'Windows dry-run deployed configuration'
        Reject { & $InstallEntry -Resume $Temp -DryRun -OnlyStage packages }
        Reject { & $InstallEntry -Resume $Temp -DryRun -NoChinaMirrors }
        Write-DataContractRows workflow-request @('windows|windows|0|configuration||1') (Join-Path $Temp 'request.tsv')
        foreach ($Code in @(23,75,130)) {
            Complete-StageResult $Metadata $Code $true ''
            $Text = @(& $StatusEntry -Session $Temp) -join "`n"
            Assert ($Text.Contains('original command with -DryRun') -and -not $Text.Contains('-Resume')) 'Dry-run status recommended resume'
        }
        Reject { & $InstallEntry -Resume $Temp -DryRun }
    } finally { foreach ($Name in $OldEnvironment.Keys) { [Environment]::SetEnvironmentVariable($Name, $OldEnvironment[$Name]) } }
    Write-DataContractRows workflow-request @('windows|windows|0|packages||0') (Join-Path $Temp 'request.tsv')
    $Row.stage = 'packages'; $Row.report = Join-Path $Temp 'packages.tsv'
    Write-DataContractRows install-result @('docker|failed|1|exit-23||||') $Row.report
    Write-AtomicReport (Join-Path $Temp 'workflow.json') (ConvertTo-Json -InputObject @($Row))
    $Text = @(& $StatusEntry -Session $Temp) -join "`n"
    Assert ($Text.Contains('Item docker: failed (exit-23)') -and -not $Text.Contains('restore')) 'Incorrect package failure advice'
    'corrupt' | Set-Content (Join-Path $Temp 'packages.result')
    Reject { & $StatusEntry -Session $Temp }
    'PowerShell workflow resume entry and failure summary tests passed.'
} finally { Remove-Item -LiteralPath $Temp -Recurse -Force }
