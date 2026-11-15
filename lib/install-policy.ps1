function Get-InstallExecutionPolicy {
    param([string]$Method = '*', [string]$Operation = 'install', [string]$Path = (Join-Path $PSScriptRoot '../install/schema/execution.tsv'))
    $Methods = @(Get-Content (Join-Path $PSScriptRoot '../install/schema/methods.tsv') | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $_.Split("`t")[0] })
    $Policies = @{}
    foreach ($Line in Get-Content -LiteralPath $Path) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Cells = $Line.Split("`t")
        if ($Cells.Count -ne 4) { throw 'Invalid installation execution policy' }
        $Name, $Op, $Timeout, $Codes = $Cells
        $Key = "$Name/$Op"
        if (($Name -ne '*' -and $Name -cnotin $Methods) -or $Op -cnotin @('probe','install','download','modify') -or $Timeout -cnotmatch '^(0|[1-9][0-9]*)$' -or $Timeout.Length -gt 5 -or [int]$Timeout -gt 86400 -or $Policies.ContainsKey($Key)) { throw 'Invalid installation execution policy' }
        $Accepted = @()
        foreach ($Code in $Codes.Split(',')) {
            if ($Code -cnotmatch '^(0|[1-9][0-9]*)$' -or $Code.Length -gt 5 -or [int]$Code -gt 65535 -or [int]$Code -in @(124,130,143) -or [int]$Code -in $Accepted) { throw 'Invalid installation success code' }
            $Accepted += [int]$Code
        }
        if (0 -notin $Accepted -or ($Op -in @('probe','download') -and $Codes -ne '0')) { throw 'Invalid success policy for operation' }
        $Policies[$Key] = @{ TimeoutSeconds = [int]$Timeout; SuccessCodes = $Accepted }
    }
    foreach ($Op in @('probe','install','download','modify')) { if (-not $Policies.ContainsKey("*/$Op")) { throw "Missing default execution policy: $Op" } }
    $Key = "$Method/$Operation"
    if (-not $Policies.ContainsKey($Key)) { $Key = "*/$Operation" }
    if (-not $Policies.ContainsKey($Key)) { throw "Unknown execution operation: $Operation" }
    $Policies[$Key]
}
