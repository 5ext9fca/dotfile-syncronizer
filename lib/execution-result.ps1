function Get-ExecutionResult {
    param([int]$Code, [bool]$DryRun = $false)
    if ($Code -eq 0 -and $DryRun) { return @{ Status = 'planned'; Reason = 'dry-run' } }
    foreach ($Line in Get-Content -LiteralPath (Join-Path $PSScriptRoot '../workflow/schema/outcomes.tsv')) {
        if ($Line.StartsWith('#')) { continue }
        $Fields = $Line.Split("`t")
        if ($Fields[0] -eq [string]$Code) { return @{ Status = $Fields[1]; Reason = $Fields[2] } }
    }
    return @{ Status = 'failed'; Reason = "exit-$Code" }
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
