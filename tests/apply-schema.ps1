$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/apply-items.ps1')
$Root = Join-Path $PSScriptRoot 'fixtures/apply'; $Count = 0
foreach ($Line in Get-Content (Join-Path $Root 'cases.tsv')) {
    if (-not $Line -or $Line.StartsWith('#')) { continue }
    $Name, $Platform, $Outcome = $Line.Split("`t"); $Failed = $false
    try {
        $Items = @(Read-ApplyItems (Join-Path $Root $Name) $Platform)
        $Actual = @($Items | ForEach-Object { "$($_.id)|$($_.source)|$($_.target_root)|$($_.target)|$($_.method)|$($_.exclude)|$($_.condition)|$($_.renderer)" })
    } catch { $Failed = $true }
    if ($Outcome -eq 'error') { if (-not $Failed) { throw "Accepted $Name" } }
    else {
        if ($Failed) { throw "Rejected $Name" }
        $Expected = @(Get-Content (Join-Path $Root "$Name/expected.txt"))
        if (($Actual -join "`n") -cne ($Expected -join "`n")) { throw "Mismatch: $Name" }
    }
    $Count++
}
Write-Host "Apply schema tests passed ($Count shared cases)."
