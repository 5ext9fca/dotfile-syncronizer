. (Join-Path $PSScriptRoot 'python.ps1')
function Get-InstallDecision {
    param([string]$State, [ValidateSet('normal', 'resume')][string]$Mode, [bool]$Discovery = $false)
    Invoke-DotfilesRule install-decision @{state=$State;mode=$Mode;discovery=[int]$Discovery} -AsHashtable
}
