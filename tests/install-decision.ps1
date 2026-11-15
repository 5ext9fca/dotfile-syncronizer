$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/install-items.ps1')
foreach ($Line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/install/decisions.tsv')) {
    if ($Line.StartsWith('#')) { continue }
    $State, $Mode, $Check, $Legacy, $Action, $Reason, $ResultState = $Line.Split('|')
    # Legacy command execution is Unix-only; Windows discovers command paths.
    if ($Check) { continue }
    $Actual = Get-InstallDecision $State $Mode
    if ("$($Actual.Action)|$($Actual.Reason)|$($Actual.State)|$($Actual.DecisionReason)" -cne "$Action|$Reason|$ResultState|$Reason") { throw "Decision mismatch: $Line" }
}
foreach ($Case in @(@('unknown', 'normal'), @('', 'invalid'))) {
    $Failed = $false
    try { Get-InstallDecision $Case[0] $Case[1] } catch { $Failed = $true }
    if (-not $Failed) { throw 'Invalid decision input was accepted' }
}
Write-Host 'Pure installation decision policy passed.'
