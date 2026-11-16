# Declaration validation is shared; native filesystem observations stay in apply-fs.
. (Join-Path $PSScriptRoot 'python.ps1')
function Read-ApplyItems {
    param([string]$Directory, [string]$Platform = 'windows')
    foreach ($Item in @(Invoke-DotfilesRequest apply-items @{directory=$Directory;platform=$Platform})) {
        ConvertTo-DotfilesRecord $Item
    }
}
