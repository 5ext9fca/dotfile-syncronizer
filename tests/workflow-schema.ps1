$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/workflow-profile.ps1')
. (Join-Path $RepoRoot 'lib/workflow-stages.ps1')
$Fixtures = Join-Path $PSScriptRoot 'fixtures/workflow'
$Canonical = @(Get-Content -LiteralPath (Join-Path $Fixtures 'expected.txt')) -join "`n"
$Count = 0
foreach ($Case in Get-Content -LiteralPath (Join-Path $Fixtures 'cases.tsv')) {
    $Name, $Expected = $Case.Split("`t")
    $Failed = $false; $Actual = @()
    try { $Actual = @(ConvertTo-WorkflowProfileText (Read-WorkflowProfile (Join-Path $Fixtures "$Name.conf"))) }
    catch { $Failed = $true }
    if ($Expected -eq 'valid') {
        if ($Failed -or ($Actual -join "`n") -cne $Canonical) { throw "Invalid canonical output for $Name" }
    } elseif (-not $Failed -or $Actual.Count) { throw "Accepted invalid/partial profile $Name" }
    $Count++
}
Write-Host "Workflow schema tests passed ($Count shared fixtures)."

$Count = 0
foreach ($Case in Get-Content -LiteralPath (Join-Path $Fixtures 'stages/cases.tsv')) {
    $Name, $Platform, $Profile, $Only, $From, $Mirrors, $Registry, $Expected = $Case.Split("`t")
    if ($Only -eq '-') { $Only = '' }; if ($From -eq '-') { $From = '' }
    $Registry = if ($Registry -eq '-') { Join-Path $Fixtures 'stages/legacy.tsv' } else { Join-Path $Fixtures "stages/$Registry" }
    $ProfileData = Read-WorkflowProfile (Join-Path $Fixtures "stages/$Profile.conf")
    $Actual = @(); $Failed = $false
    try { $Actual = @(ConvertTo-WorkflowStagePlanText @(Get-WorkflowStagePlan $Platform $ProfileData $Only $From ($Mirrors -eq '1') $Registry)) }
    catch { $Failed = $true }
    if ($Expected -eq 'valid') {
        $Canonical = @(Get-Content -LiteralPath (Join-Path $Fixtures "stages/$Name.expected")) -join "`n"
        if ($Failed -or ($Actual -join "`n") -cne $Canonical) { throw "Invalid canonical stage plan for $Name" }
    } elseif (-not $Failed -or $Actual.Count) { throw "Accepted invalid/partial stage plan $Name" }
    $Count++
}
Write-Host "Workflow stage tests passed ($Count shared fixtures)."
