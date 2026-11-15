# Shared stage definitions, selection and gates. PowerShell 5.1 compatible.
function Read-WorkflowStages {
    param([string]$Platform, [string]$Path = (Join-Path $PSScriptRoot '../workflow/schema/stages.tsv'))
    $Records = @(); $Seen = @{}
    foreach ($Line in Get-Content -LiteralPath $Path) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Parts = $Line.Split("`t")
        if ($Parts.Count -ne 6) { throw 'Invalid stage registry row' }
        $HostName, $Order, $Id, $Gate, $Preflight, $Action = $Parts
        if ($HostName -cnotin @('unix', 'windows') -or $Order -cnotmatch '^[0-9]+$' -or $Order.Length -gt 6 -or $Id -cnotmatch '^[a-z][a-z0-9-]*$' -or $Gate -cnotin @('always', 'mirrors', 'shell', 'wsl')) { throw 'Invalid stage registry fields' }
        foreach ($Handler in @($Preflight, $Action)) {
            if ($Handler -cnotin @('packages', 'git', 'configuration', 'mirrors', 'shell', 'wsl')) { throw 'Invalid stage handler' }
        }
        if ($HostName -ceq 'unix' -and ($Preflight -cin @('git', 'wsl') -or $Action -cin @('git', 'wsl'))) { throw 'Unsupported Unix handler' }
        if ($HostName -ceq 'windows' -and ($Preflight -cin @('mirrors', 'shell') -or $Action -cin @('mirrors', 'shell'))) { throw 'Unsupported Windows handler' }
        if ($Seen.ContainsKey("$HostName/$Id")) { throw "Duplicate stage $Id" }
        $Seen["$HostName/$Id"] = $true
        if ($HostName -ceq $Platform) { $Records += [pscustomobject]@{ Id = $Id; Order = [int]$Order; Gate = $Gate; Preflight = $Preflight; Action = $Action } }
    }
    if (-not $Records.Count) { throw "Unknown stage platform $Platform" }
    $Done = @{}
    while ($Done.Count -lt $Records.Count) {
        $Best = $null
        foreach ($Record in $Records) {
            if ($Done.ContainsKey($Record.Id)) { continue }
            if (-not $Best -or $Record.Order -lt $Best.Order -or ($Record.Order -eq $Best.Order -and [StringComparer]::Ordinal.Compare($Record.Id, $Best.Id) -lt 0)) { $Best = $Record }
        }
        $Done[$Best.Id] = $true
        $Best
    }
}
function Get-WorkflowStagePlan {
    param([string]$Platform, [hashtable]$Profile, [string]$OnlyStage, [string]$FromStage, [bool]$Mirrors = $true,
        [string]$Registry = (Join-Path $PSScriptRoot '../workflow/schema/stages.tsv'))
    if ($OnlyStage -and $FromStage) { throw 'OnlyStage and FromStage are mutually exclusive' }
    $Records = @(Read-WorkflowStages $Platform $Registry)
    foreach ($Value in @($OnlyStage, $FromStage)) {
        if ($Value -and $Value -cnotin @($Records.Id)) { throw "Unknown workflow stage $Value" }
    }
    $Reached = -not [bool]$FromStage
    foreach ($Record in $Records) {
        if ($Record.Id -ceq $FromStage) { $Reached = $true }
        $Enabled = $Reached -and (-not $OnlyStage -or $OnlyStage -ceq $Record.Id)
        $Reason = if ($Enabled) { '' } else { 'selection' }
        if ($Enabled -and $Record.Gate -cne 'always' -and $Profile[$Record.Gate] -ceq 'none') { $Enabled = $false; $Reason = 'profile' }
        if ($Enabled -and $Record.Gate -ceq 'mirrors' -and -not $Mirrors) { $Enabled = $false; $Reason = 'disabled' }
        [pscustomobject]@{ Id = $Record.Id; Enabled = $Enabled; Reason = $Reason; Preflight = $Record.Preflight; Action = $Record.Action }
    }
}
function ConvertTo-WorkflowStagePlanText {
    param([object[]]$Plan)
    foreach ($Stage in $Plan) { "$($Stage.Id)|$([int]$Stage.Enabled)|$($Stage.Reason)|$($Stage.Preflight)|$($Stage.Action)" }
}
