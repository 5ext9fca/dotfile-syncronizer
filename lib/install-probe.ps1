$InstallProbeRules = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../install/schema/probes.tsv'))
function Get-InstallProbeResult {
    param([string]$State)
    if ($State -match '[|\r\n]') { throw 'Invalid installation probe delimiters' }
    foreach ($Line in $InstallProbeRules) {
        if ($Line.StartsWith('#')) { continue }
        $Fields = $Line.Split("`t")
        if ($State -cmatch $Fields[0]) { return @{ Action = $Fields[1]; Reason = $Fields[2] } }
    }
    throw "Invalid installation probe state: $State"
}
