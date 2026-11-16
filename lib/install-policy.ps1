. (Join-Path $PSScriptRoot 'python.ps1')
function Get-InstallExecutionPolicy {
    param([string]$Method = '*', [string]$Operation = 'install', [string]$Path = '')
    if (-not $Path) { $Path = if ($script:DotfilesExecutionPolicyPath) { $script:DotfilesExecutionPolicyPath } else { Join-Path $PSScriptRoot '../install/schema/execution.tsv' } }
    Invoke-DotfilesRule execution-policy @{method=$Method;'native-operation'=$Operation;path=$Path} -AsHashtable
}
