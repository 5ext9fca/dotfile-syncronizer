function New-InstallResultRow {
    param([hashtable]$Item, [string]$Status, [int]$Elapsed, [string]$Reason, [bool]$Observed = $true)
    Invoke-DotfilesRequest install-result-row @{item=$Item;status=$Status;elapsed=$Elapsed;reason=$Reason;observed=[int]$Observed}
}
function Read-InstallResult {
    param([string]$Text)
    foreach ($Value in @(Invoke-DotfilesRequest install-result-read @{text=$Text})) { ConvertTo-DotfilesRecord $Value }
}
function Show-InstallResult {
    param([object[]]$Items)
    Invoke-DotfilesRequest install-result-show @{records=@($Items)}
}
