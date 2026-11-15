function New-InstallResultRow {
    param([hashtable]$Item, [string]$Status, [int]$Elapsed, [string]$Reason, [bool]$Observed = $true)
    $Result = @{ id=$Item.id; status=$Status; elapsed_seconds=$Elapsed; reason=$Reason; selected_method=$Item.method }
    foreach ($Field in @('detected_method', 'detected_paths', 'decision_reason')) {
        $Result[$Field] = if ($Observed) { [string]$Item[$Field] } else { '' }
    }
    ((Get-DataContractFields install-result | ForEach-Object { [string]$Result[$_] }) -join '|')
}
function Read-InstallResult {
    param([string]$Text)
    if (($Text -split "`n")[0].TrimEnd("`r") -ceq '# dotfiles|install-result|1') {
        $Fields = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../contracts/schema/install-result-v1.fields'))
        foreach ($Item in @(Read-DataContractSchema install-result $Text 1 $Fields)) {
            foreach ($Field in Get-DataContractFields install-result) { if (-not $Item.ContainsKey($Field)) { $Item[$Field] = '' } }
            $Item
        }
    } else { Read-DataContract install-result $Text }
}
function Show-InstallResult {
    param([object[]]$Items)
    foreach ($Item in $Items) {
        if ($Item.status -notin @('failed','deferred','interrupted','running','skipped','blocked')) { continue }
        "  Item $($Item.id): $($Item.status) ($($Item.reason))"
        if ($Item.selected_method) { "    Preferred method: $($Item.selected_method)" }
        if ($Item.decision_reason) { "    Decision: $($Item.decision_reason)" }
        if ($Item.detected_method) {
            "    Matched method: $($Item.detected_method)"
            "    Matched paths (JSON): $($Item.detected_paths)"
        }
    }
}
