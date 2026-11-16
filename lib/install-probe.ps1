. (Join-Path $PSScriptRoot 'python.ps1')
function Get-InstallProbeResult {
    param([string]$State)
    Invoke-DotfilesRule probe-result @{state=$State} -AsHashtable
}
