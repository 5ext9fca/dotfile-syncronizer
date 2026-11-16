. (Join-Path $PSScriptRoot 'python.ps1')
function Get-ExecutionResult {
    param([int]$Code, [bool]$DryRun = $false)
    Invoke-DotfilesRule execution-result @{code=$Code;dry=[int]$DryRun} -AsHashtable
}
function New-ExecutionException {
    param([string]$Message, [int]$Code)
    $Exception = [Exception]::new($Message)
    $Exception.Data['ExitCode'] = $Code
    return $Exception
}
function Get-ExecutionExceptionCode {
    param([Exception]$Exception)
    if ($Exception.Data.Contains('ExitCode')) { return [int]$Exception.Data['ExitCode'] }
    if ($Exception -is [System.Management.Automation.PipelineStoppedException] -or $Exception -is [OperationCanceledException]) { return 130 }
    return 1
}
