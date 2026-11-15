. (Join-Path $PSScriptRoot 'command.ps1')
. (Join-Path $PSScriptRoot 'install-policy.ps1')

function Invoke-InstallCommand {
    param([hashtable]$Context, [string]$Command, [object[]]$Arguments, [int[]]$SuccessCodes, [string]$Method, [string]$Operation = 'install')
    if (-not $Method) { $Method = $Context.Method }
    $Policy = Get-InstallExecutionPolicy $Method $Operation
    if (-not $PSBoundParameters.ContainsKey('SuccessCodes')) { $SuccessCodes = $Policy.SuccessCodes }
    $Result = Invoke-ManagedCommand mutation $Command $Arguments -DryRun ([bool]$Context.DryRun) -TimeoutSeconds $Policy.TimeoutSeconds -Stream
    if ($Result.ExitCode -notin $SuccessCodes) {
        throw (New-ExecutionException "$Command failed with exit code $($Result.ExitCode)" $Result.ExitCode)
    }
}
