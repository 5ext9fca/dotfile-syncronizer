. (Join-Path $PSScriptRoot 'data-contract.ps1')
. (Join-Path $PSScriptRoot 'atomic-report.ps1')
function Read-StageResult {
    param([string]$Path)
    Invoke-DotfilesRequest 'stage-read' @{ text = [IO.File]::ReadAllText($Path) }
}
function Initialize-StageResult {
    param([string]$Path, [string]$Stage, [string]$Report)
    $Document = Invoke-DotfilesRequest 'stage-init' @{ stage = $Stage; report = $Report }
    Write-AtomicReport $Path $Document -CreateNew
}
function Set-StageResultValue {
    param([string]$Path, [string]$Key, [string]$Value, [switch]$Append)
    if (-not $Path) { return }
    $Update = Invoke-DotfilesRequest 'stage-update' @{ text = [IO.File]::ReadAllText($Path); key = $Key; value = $Value; append = [int]$Append.IsPresent }
    if ($Update.changed) { Write-AtomicReport $Path $Update.document }
}
function Complete-StageResult {
    param([string]$Path, [int]$Code, [bool]$DryRun, [string]$Report)
    $Exists = $Report -and (Test-Path -LiteralPath $Report -PathType Leaf)
    $Document = Invoke-DotfilesRequest 'stage-finish' @{ text = [IO.File]::ReadAllText($Path); code = $Code; dry = [int]$DryRun; report = $Report; report_exists = [int]$Exists }
    Write-AtomicReport $Path $Document
}
