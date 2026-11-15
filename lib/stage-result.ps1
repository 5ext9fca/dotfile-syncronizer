. (Join-Path $PSScriptRoot 'data-contract.ps1')
. (Join-Path $PSScriptRoot 'atomic-report.ps1')
. (Join-Path $PSScriptRoot 'execution-result.ps1')
function Read-StageResult {
    param([string]$Path)
    $Rows = @(Read-DataContract 'stage-result' ([IO.File]::ReadAllText($Path)))
    $Required = @('stage', 'status', 'exit_code', 'retry_stage', 'reason', 'report'); $Seen = @{}
    foreach ($Row in $Rows) {
        if ($Row.key -cnotin ($Required + @('recovery_journal', 'child_report'))) { throw 'Unknown stage result field' }
        if ($Row.key -cin $Required -and $Seen.ContainsKey($Row.key)) { throw 'Duplicate stage result field' }
        $Seen[$Row.key] = $true
        if ($Row.key -ceq 'stage' -and $Row.value -cnotmatch '^[a-z][a-z0-9-]*$') { throw 'Invalid stage ID' }
        if ($Row.key -ceq 'status' -and $Row.value -cnotin @('running', 'success', 'planned', 'failed', 'deferred', 'interrupted')) { throw 'Invalid stage status' }
        if ($Row.key -ceq 'exit_code' -and $Row.value -cnotmatch '^[0-9]+$') { throw 'Invalid stage exit code' }
    }
    foreach ($Key in $Required) { if (-not $Seen.ContainsKey($Key)) { throw "Missing stage result $Key" } }
    $Rows
}
function Initialize-StageResult {
    param([string]$Path, [string]$Stage, [string]$Report)
    $Rows = @(@{ key = 'stage'; value = $Stage }, @{ key = 'status'; value = 'running' }, @{ key = 'exit_code'; value = '0' }, @{ key = 'retry_stage'; value = $Stage }, @{ key = 'reason'; value = 'started' }, @{ key = 'report'; value = $Report })
    Write-AtomicReport $Path (ConvertTo-DataContract 'stage-result' $Rows) -CreateNew
}
function Set-StageResultValue {
    param([string]$Path, [string]$Key, [string]$Value, [switch]$Append)
    if (-not $Path) { return }
    $Rows = @(Read-StageResult $Path)
    if ($Append) {
        if ($Key -cnotin @('recovery_journal', 'child_report')) { throw 'Invalid artifact kind' }
        if (@($Rows | Where-Object { $_.key -ceq $Key -and $_.value -ceq $Value }).Count) { return }
    } else { $Rows = @($Rows | Where-Object { $_.key -cne $Key }) }
    $Rows += @{ key = $Key; value = $Value }
    Write-AtomicReport $Path (ConvertTo-DataContract 'stage-result' $Rows)
}
function Complete-StageResult {
    param([string]$Path, [int]$Code, [bool]$DryRun, [string]$Report)
    $Rows = @(Read-StageResult $Path); $Stage = ($Rows | Where-Object key -eq 'stage').value
    $Outcome = Get-ExecutionResult $Code $DryRun
    $Rows = @($Rows | Where-Object { $_.key -cin @('stage', 'recovery_journal', 'child_report') })
    $Rows += @(@{ key = 'status'; value = $Outcome.Status }, @{ key = 'exit_code'; value = [string]$Code }, @{ key = 'reason'; value = $Outcome.Reason }, @{ key = 'retry_stage'; value = $(if ($Code) { $Stage } else { '' }) }, @{ key = 'report'; value = $(if ($Report -and (Test-Path -LiteralPath $Report -PathType Leaf)) { $Report } else { '' }) })
    Write-AtomicReport $Path (ConvertTo-DataContract 'stage-result' $Rows)
}
