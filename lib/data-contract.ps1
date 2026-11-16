. (Join-Path $PSScriptRoot 'python.ps1')
function Get-DataContractFields {
    param([string]$Kind)
    Invoke-DotfilesRequest contract-fields @{kind=$Kind}
}
function Get-DataContractVersion {
    param([string]$Kind)
    Invoke-DotfilesRequest contract-version @{kind=$Kind}
}
function Read-DataContract {
    param([string]$Kind, [string]$Text)
    foreach ($Value in @(Invoke-DotfilesRequest contract-read @{kind=$Kind;text=$Text})) { ConvertTo-DotfilesRecord $Value }
}
function Read-DataContractSchema {
    param([string]$Kind, [string]$Text, [int]$Version, [string[]]$Fields)
    foreach ($Value in @(Invoke-DotfilesRequest contract-read-schema @{kind=$Kind;text=$Text;version=$Version;fields=$Fields})) { ConvertTo-DotfilesRecord $Value }
}
function ConvertTo-DataContract {
    param([string]$Kind, [object[]]$Records)
    $Values = @()
    if ($null -ne $Records) { $Values = @($Records) }
    Invoke-DotfilesRequest contract-write @{kind=$Kind;records=$Values}
}
function Write-DataContractRows {
    param([string]$Kind, [string[]]$Rows, [string]$Path)
    $Text = Invoke-DotfilesRequest contract-write @{kind=$Kind;text=($Rows -join "`n")}
    Write-AtomicReport $Path $Text
}
