function Get-DataContractFields {
    param([string]$Kind)
    if ($Kind -cnotmatch '^[a-z][a-z-]*$') { throw 'Invalid contract kind' }
    @(Get-Content -LiteralPath (Join-Path $PSScriptRoot "../contracts/schema/$Kind.fields") -ErrorAction Stop)
}
function Get-DataContractVersion {
    param([string]$Kind)
    foreach ($Line in Get-Content -LiteralPath (Join-Path $PSScriptRoot '../contracts/schema/types.tsv')) {
        $Parts = $Line.Split("`t")
        if ($Parts[0] -ceq $Kind) { return [int]$Parts[1] }
    }
    throw "Unknown contract kind: $Kind"
}
function Read-DataContract {
    param([string]$Kind, [string]$Text)
    $Fields = @(Get-DataContractFields $Kind); $Version = Get-DataContractVersion $Kind
    Read-DataContractSchema $Kind $Text $Version $Fields
}
# Used only by explicit adapters for known historical report schemas.
function Read-DataContractSchema {
    param([string]$Kind, [string]$Text, [int]$Version, [string[]]$Fields)
    $Lines = @($Text.TrimEnd("`n").Split("`n") | ForEach-Object { $_.TrimEnd("`r") })
    if ($Lines.Count -lt 2 -or $Lines[0] -cne "# dotfiles|$Kind|$Version") { throw "Unknown or missing $Kind version" }
    $Columns = $Lines[1].Split('|'); $Seen = @{}
    if ($Columns.Count -ne $Fields.Count) { throw 'Wrong contract field count' }
    foreach ($Column in $Columns) {
        if ($Column -cnotin $Fields -or $Seen.ContainsKey($Column)) { throw 'Unknown or duplicate contract field' }
        $Seen[$Column] = $true
    }
    $Records = @()
    foreach ($Line in $Lines | Select-Object -Skip 2) {
        $Cells = $Line.Split('|')
        if ($Cells.Count -ne $Fields.Count -or $Line -match '[\r\t]') { throw 'Malformed contract record' }
        $Record = @{}
        for ($Index = 0; $Index -lt $Columns.Count; $Index++) { $Record[$Columns[$Index]] = $Cells[$Index] }
        $Records += $Record
    }
    $Records
}
function ConvertTo-DataContract {
    param([string]$Kind, [object[]]$Records)
    $Fields = @(Get-DataContractFields $Kind); $Version = Get-DataContractVersion $Kind
    $Lines = @("# dotfiles|$Kind|$Version", ($Fields -join '|'))
    foreach ($Record in $Records) {
        $Cells = @($Fields | ForEach-Object { [string]$Record[$_] })
        foreach ($Cell in $Cells) { if ($Cell -match '[|\r\n\t]') { throw 'Unsupported contract field delimiter' } }
        $Lines += ($Cells -join '|')
    }
    $Text = $Lines -join "`n"
    $null = @(Read-DataContract $Kind $Text)
    return $Text
}
function Write-DataContractRows {
    param([string]$Kind, [string[]]$Rows, [string]$Path)
    $Header = "# dotfiles|$Kind|$(Get-DataContractVersion $Kind)`n$((Get-DataContractFields $Kind) -join '|')"
    $Text = $Header + $(if ($Rows.Count) { "`n" + ($Rows -join "`n") } else { '' })
    $null = @(Read-DataContract $Kind $Text)
    Write-AtomicReport $Path $Text
}
