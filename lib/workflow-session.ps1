# Session lifetime and durable stage reports.
. (Join-Path $PSScriptRoot 'atomic-report.ps1')
function Invoke-WorkflowStagesUnlocked {
    param([hashtable]$Context, [hashtable]$Actions)
    $SessionId = $Context.SessionId; $SessionPath = $Context.SessionPath
    $DryRun = $Context.DryRun; $ResultsPath = $Context.ResultsPath
    $Persistent = -not $DryRun -or [bool]$ResultsPath
    $Directory = if ($Persistent) { $SessionPath } else { Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-workflow-' + [guid]::NewGuid().ToString('N')) }
    $null = New-Item -ItemType Directory -Path $Directory
    Save-WorkflowRequest $Context $Directory
    $RetryStage = ''; $Results = @(); $Failure = $null
    Write-Host "Workflow session: $SessionId"
    try {
        # Reserve the explicit report before any stage mutation, proving that
        # its destination is writable without risking an existing file.
        if ($ResultsPath) { Write-AtomicReport $ResultsPath '[]' -CreateNew }
        foreach ($StageDefinition in $Context.StagePlan) {
            $Stage = $StageDefinition.Id
            $Timer = [Diagnostics.Stopwatch]::StartNew()
            $Log = ''; $Report = ''; $Journal = ''; $ChildReport = ''; $Code = 0; $Reason = ''
            if (-not $StageDefinition.Enabled) { $Status = 'skipped'; $Reason = $StageDefinition.Reason }
            elseif ($Failure) { $Status = 'blocked'; $Reason = 'previous-stage-failed' }
            else {
                $Log = Join-Path $Directory "$Stage.log"
                $Report = Join-Path $Directory "$Stage.tsv"
                # A durable start record survives abrupt host or child termination.
                $Running = [pscustomobject][ordered]@{ schema_version = 1; session = $SessionId; profile = $Context.ProfileName; stage = $Stage; status = 'running'; exit_code = 0; elapsed_seconds = 0; log = $Log; report = $Report; recovery_journal = ''; child_report = ''; reason = 'started'; retry_stage = $Stage }
                if ($Persistent) {
                    $Snapshot = ConvertTo-Json -InputObject @(@($Results) + @($Running)) -Depth 5
                    Write-AtomicReport (Join-Path $Directory 'workflow.json') $Snapshot
                    if ($ResultsPath) { Write-AtomicReport $ResultsPath $Snapshot }
                }
                $StageResultPath = Join-Path $Directory "$Stage.result"
                Initialize-StageResult $StageResultPath $Stage $Report
                $Writer = [IO.File]::CreateText($Log)
                $Writer.AutoFlush = $true
                try {
                    & $Actions[$StageDefinition.Action] $Context $Report $StageResultPath *>&1 | ForEach-Object {
                        $Line = $_.ToString()
                        $Writer.WriteLine($Line)
                        Write-Host $Line
                    }
                    $Status = if ($DryRun) { 'planned' } else { 'success' }
                } catch {
                    $Failure = $_; $Code = Get-ExecutionExceptionCode $_.Exception; $Outcome = Get-ExecutionResult $Code $DryRun; $Status = $Outcome.Status; $Reason = $_.Exception.Message; $RetryStage = $Stage
                    $Writer.WriteLine($Reason)
                    Write-Warning $Reason
                } finally { $Writer.Dispose() }
                try {
                    Complete-StageResult $StageResultPath $Code $DryRun $Report
                    $StageRows = @(Read-StageResult $StageResultPath)
                    $Journal = (@($StageRows | Where-Object key -eq 'recovery_journal' | ForEach-Object { $_.value }) -join ',')
                    $ChildReport = (@($StageRows | Where-Object key -eq 'child_report' | ForEach-Object { $_.value }) -join ',')
                } catch {
                    $Failure = $_; $Status = 'failed'; $Code = 65; $Reason = 'invalid-stage-result'; $RetryStage = $Stage
                }
                if (-not (Test-Path -LiteralPath $Report)) { $Report = '' }
                if (-not $Persistent) { $Log = ''; $Report = '' }
            }
            $Timer.Stop()
            $Results += [pscustomobject][ordered]@{
                schema_version = 1; session = $SessionId; profile = $Context.ProfileName; stage = $Stage; status = $Status; retry_stage = $RetryStage
                exit_code = $Code; elapsed_seconds = [int]$Timer.Elapsed.TotalSeconds
                log = $Log; report = $Report; recovery_journal = $Journal; child_report = $ChildReport; reason = $Reason
            }
            # Persist after every stage, including failure/blocked rows.
            if ($Persistent) {
                $Snapshot = ConvertTo-Json -InputObject @($Results) -Depth 5
                Write-AtomicReport (Join-Path $Directory 'workflow.json') $Snapshot
                if ($ResultsPath) { Write-AtomicReport $ResultsPath $Snapshot }
            }
            Write-Host "Stage ${Stage}: $Status"
        }
        if ($Persistent) { Write-Host "Workflow report: $(Join-Path $Directory 'workflow.json')" }
        if ($Failure) {
            $QuotedSession = "'" + $SessionPath.Replace("'", "''") + "'"
            if ($Persistent) { Write-Warning "Inspect failure: ./workflow/status.ps1 -Session $QuotedSession" }
            if ($Persistent -and -not $DryRun) { Write-Warning "After resolving the cause, continue with -Resume $QuotedSession; current state is checked again." }
            else { Write-Warning 'Retry with -FromStage STAGE or -OnlyStage STAGE; current state is checked again.' }
            throw $Failure
        }
    } finally {
        if (-not $Persistent) { Remove-Item -LiteralPath $Directory -Recurse -Force }
    }
}


function Invoke-WorkflowStages {
    param([hashtable]$Context, [hashtable]$Actions)
    Invoke-DeploymentLocked $Context.DryRun { Invoke-WorkflowStagesUnlocked $Context $Actions }
}
