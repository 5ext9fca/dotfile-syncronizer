function New-InstallFixture {
    param([string]$Root, [string]$Name, [string]$Destination)
    $Patch = Join-Path $Root "$Name/edits.tsv"
    if (-not (Test-Path -LiteralPath $Patch)) { return Join-Path $Root $Name }
    $Lines = @(Get-Content -LiteralPath (Join-Path $Root 'discovery/tool.conf'))
    $Deleted = @{}; $Prefix = @{}
    foreach ($Edit in Get-Content -LiteralPath $Patch) {
        if ($Edit.StartsWith('#')) { continue }
        $Parts = $Edit.Split("`t")
        if ($Parts.Count -ne 4 -or $Parts[1] -notmatch '^[0-9]+$') { throw 'Malformed fixture edit' }
        $Number = [int]$Parts[1]
        if ($Number -lt 1 -or $Number -gt $Lines.Count + 1) { throw 'Fixture edit is out of range' }
        switch ($Parts[0]) {
            'delete' {
                if ($Deleted.ContainsKey($Number) -or $Number -gt $Lines.Count -or $Lines[$Number - 1] -cne $Parts[2]) { throw 'Fixture edit does not match base' }
                $Deleted[$Number] = $true
            }
            'insert' { $Prefix[$Number] = @($Prefix[$Number] | Where-Object { $null -ne $_ }) + @($Parts[3]) }
            default { throw 'Unknown fixture edit operation' }
        }
    }
    $Output = @()
    for ($Number = 1; $Number -le $Lines.Count + 1; $Number++) {
        if ($Prefix.ContainsKey($Number)) { $Output += $Prefix[$Number] }
        if ($Number -le $Lines.Count -and -not $Deleted.ContainsKey($Number)) { $Output += $Lines[$Number - 1] }
    }
    $Directory = Join-Path $Destination $Name
    $null = New-Item -ItemType Directory -Path $Directory -Force
    [IO.File]::WriteAllLines((Join-Path $Directory 'tool.conf'), [string[]]$Output)
    $Directory
}
