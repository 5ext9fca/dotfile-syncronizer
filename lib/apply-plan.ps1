# Full component planning before the first filesystem mutation.
function Test-ApplyVirtual {
    param([string]$Path, [hashtable]$State)
    foreach ($Known in $State.Directories.Keys) { if ($State.Directories[$Known] -and (Test-ApplyWithin $Path $Known)) { return $true } }
    return $false
}
function Add-ApplyDirectory {
    param([string]$Component, [string]$Path, [string]$Root, [hashtable]$State)
    if ($Path -eq $Root -or $State.Directories.ContainsKey($Path)) { return }
    $Parent = [IO.Path]::GetDirectoryName($Path)
    Add-ApplyDirectory $Component $Parent $Root $State
    $Entry = Get-ApplyEntry $Path
    if (-not (Test-ApplyVirtual $Parent $State) -and $Entry -and $Entry.PSIsContainer -and -not (Test-ApplyLink $Entry)) { $State.Directories[$Path] = $false; return }
    $Before = if (Test-ApplyVirtual $Parent $State) { 'absent' } else { Get-ApplyState $Path }
    if ($Before -ne 'absent' -and $Entry.PSIsContainer -and -not (Test-ApplyLink $Entry)) { $State.Directories[$Path] = $false; return }
    $Backup = if ($Before -ne 'absent') { Join-Path $State.Session "files/$Component/$($State.Plan.Count + 1)" } else { '' }
    $State.Plan.Add(@{ Component = $Component; Action = 'mkdir'; Source = ''; Target = $Path; Backup = $Backup; Before = $Before; SourceState = ''; Root = $Root; Reason = 'directory' })
    $State.Directories[$Path] = $true
}
function Add-ApplyFile {
    param([string]$Component, [string]$Source, [string]$Target, [string]$Root, [hashtable]$State)
    $Parent = [IO.Path]::GetDirectoryName($Target)
    Add-ApplyDirectory $Component $Parent $Root $State
    $Before = if (Test-ApplyVirtual $Parent $State) { 'absent' } else { Get-ApplyState $Target }
    $Action = 'copy'; $Reason = 'new'; $Backup = ''
    if ($Before -ne 'absent') {
        $Action = 'copy'; $Reason = 'replace'; $Backup = Join-Path $State.Session "files/$Component/$($State.Plan.Count + 1)"
        if ((Get-ApplyContent $Source) -eq (Get-ApplyContent $Target)) { $Action = 'skip'; $Reason = 'unchanged'; $Backup = '' }
    }
    $State.Plan.Add(@{ Component = $Component; Action = $Action; Source = $Source; Target = $Target; Backup = $Backup; Before = $Before; SourceState = (Get-ApplyState $Source); Root = $Root; Reason = $Reason })
}
function Get-ApplyPlan {
    param([string]$RepoRoot, [string]$Items, [string]$TargetRoot, [string]$Session, [string[]]$Components = @())
    $Definitions = @(Read-ApplyItems $Items)
    foreach ($Name in $Components) { if ($Name -cnotin @($Definitions | ForEach-Object { $_.id })) { throw "Unknown component: $Name" } }
    $State = @{ Session = $Session; Plan = [Collections.Generic.List[object]]::new(); Directories = @{} }
    $Targets = @()
    foreach ($Item in $Definitions) {
        if ($Components.Count -and $Item.id -cnotin $Components) { continue }
        $Source = [IO.Path]::GetFullPath((Join-Path $RepoRoot $Item.source))
        $Target = [IO.Path]::GetFullPath((Join-Path $TargetRoot $Item.target))
        if ((Test-ApplyWithin $Target $RepoRoot) -or (Test-ApplyWithin $RepoRoot $Target) -or (Test-ApplyWithin $Session $Target) -or (Test-ApplyWithin $Target $Session)) { throw 'Source, target or backup paths overlap' }
        foreach ($Other in $Targets) { if ((Test-ApplyWithin $Target $Other) -or (Test-ApplyWithin $Other $Target)) { throw 'Overlapping component destinations' } }
        $Targets += $Target
        $Entry = Get-ApplyEntry $Source
        if (-not $Entry -or (Test-ApplyLink $Entry)) { throw "Missing or unsupported source: $Source" }
        $Probe = [IO.Path]::GetDirectoryName($Source)
        while (Test-ApplyWithin $Probe $RepoRoot) {
            if (Test-ApplyLink (Get-ApplyEntry $Probe)) { throw 'Source parent is a reparse point' }
            if ($Probe -eq $RepoRoot) { break }; $Probe = [IO.Path]::GetDirectoryName($Probe)
        }
        $Root = Get-ApplyAnchor $TargetRoot
        if ($Entry.PSIsContainer) {
            Add-ApplyDirectory $Item.id $Target $Root $State
            $Children = @{}; foreach ($Child in @(Get-ApplyTree $Source)) { $Children[$Child.FullName] = $Child }
            [string[]]$Names = @($Children.Keys); [Array]::Sort($Names, [StringComparer]::Ordinal)
            foreach ($Name in $Names) {
                $Child = $Children[$Name]; $Relative = $Name.Substring($Source.Length).TrimStart('\', '/').Replace('\', '/')
                $Excluded = $false
                foreach ($Exclude in @($Item.exclude -split ';' | Where-Object { $_ })) { if ($Relative -eq $Exclude -or $Relative.StartsWith("$Exclude/", [StringComparison]::Ordinal)) { $Excluded = $true } }
                $ChildTarget = Join-Path $Target $Relative
                if ($Excluded) { $State.Plan.Add(@{ Component = $Item.id; Action = 'skip'; Source = $Name; Target = $ChildTarget; Backup = ''; Before = ''; SourceState = ''; Root = $Root; Reason = 'excluded' }); continue }
                if (Test-ApplyLink $Child) { throw "Source is a reparse point: $Name" }
                if ($Child.PSIsContainer) { Add-ApplyDirectory $Item.id $ChildTarget $Root $State } else { Add-ApplyFile $Item.id $Name $ChildTarget $Root $State }
            }
        } else {
            if ($Item.exclude) { throw 'File components cannot have exclusions' }
            Add-ApplyFile $Item.id $Source $Target $Root $State
        }
    }
    foreach ($Operation in $State.Plan) { $Operation.schema_version = 1; $Operation }
}


function Assert-ApplyPlan {
    param([object[]]$Plan)
    foreach ($Operation in $Plan) {
        if ([string]$Operation.schema_version -cne '1') { throw 'Unsupported apply plan record version' }
        if ($Operation.Action -cnotin @('mkdir', 'copy', 'skip')) { throw 'Invalid Windows apply action' }
    }
}
function ConvertTo-ApplyPlanText {
    param([object[]]$Plan)
    Assert-ApplyPlan $Plan
    $Rows = @($Plan | ForEach-Object {
        @{ component = $_.Component; action = $_.Action; source = $_.Source; target = $_.Target; backup = $_.Backup; before = $_.Before; source_state = $_.SourceState; root = $_.Root; privilege = 'none'; reason = $_.Reason; schema_version = $_.schema_version }
    })
    ConvertTo-DataContract 'apply-plan' $Rows
}
function ConvertFrom-ApplyPlanText {
    param([string]$Text)
    $Rows = @(Read-DataContract 'apply-plan' $Text)
    $Plan = @($Rows | ForEach-Object {
        if ($_.privilege -cne 'none') { throw 'Unsupported Windows apply privilege' }
        @{ Component = $_.component; Action = $_.action; Source = $_.source; Target = $_.target; Backup = $_.backup; Before = $_.before; SourceState = $_.source_state; Root = $_.root; Reason = $_.reason; schema_version = $_.schema_version }
    })
    Assert-ApplyPlan $Plan
    $Plan
}
