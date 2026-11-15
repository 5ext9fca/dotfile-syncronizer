# Both readers use the same versioned schema and never evaluate profile values.
function Read-WorkflowProfileSchema {
    $Schema = [ordered]@{}
    foreach ($Line in Get-Content -LiteralPath (Join-Path $PSScriptRoot '../workflow/schema/profile-fields.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Key, $Pattern, $Required = $Line.Split("`t")
        $Schema[$Key] = @{ Pattern = $Pattern; Required = ($Required -eq 'yes') }
    }
    $Schema
}

function Read-WorkflowProfile {
    param([string]$Path)
    $Schema = Read-WorkflowProfileSchema
    $Profile = @{}
    foreach ($Line in Get-Content -LiteralPath $Path) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        if ($Line -cnotmatch '^([^=]+)=(.*)$') { throw 'Workflow profile: expected key=value' }
        $Key = $Matches[1]; $Value = $Matches[2]
        if ($Key -cnotin @($Schema.Keys)) { throw "Unknown profile field $Key" }
        if ($Profile.ContainsKey($Key)) { throw "Workflow profile: duplicate $Key" }
        if ($Value -cnotmatch ('^(' + $Schema[$Key].Pattern + ')$')) { throw "Invalid profile $Key" }
        if ($Key -ceq 'components') {
            $Seen = @{}
            foreach ($Pair in $Value.Split(' ')) {
                $Component = $Pair.Split(':')[0]
                if ($Seen.ContainsKey($Component)) { throw 'Duplicate component' }
                $Seen[$Component] = $true
            }
        }
        $Profile[$Key] = $Value
    }
    foreach ($Key in $Schema.Keys) {
        if ($Schema[$Key].Required -and -not $Profile.ContainsKey($Key)) { throw "Missing profile field $Key" }
    }
    $Profile
}

function ConvertTo-WorkflowProfileText {
    param([hashtable]$Profile)
    foreach ($Key in (Read-WorkflowProfileSchema).Keys) {
        if ($Profile.ContainsKey($Key)) { "$Key=$($Profile[$Key])" }
    }
}

function Select-WorkflowInstallPlan {
    param([hashtable]$Profile, [object[]]$Plan, [hashtable]$Context = @{},
        [ValidateSet('offline','normal','resume')][string]$Mode = 'offline')
    $Items = @{}; $Selected = @{}; $Pending = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($Item in $Plan) { $Items[$Item.id] = $Item }
    $Roots = if ($Profile.install -ceq 'all') { @($Plan | ForEach-Object { $_.id }) } else { $Profile.install.Split(' ') }
    foreach ($Id in $Roots) { $Pending.Enqueue($Id) }
    while ($Pending.Count) {
        $Id = $Pending.Dequeue()
        if (-not $Items.ContainsKey($Id)) { throw "Unknown profile install item $Id" }
        if ($Selected.ContainsKey($Id)) { continue }
        $Item = $Items[$Id]
        if ($Mode -ne 'offline') { $Item = Get-InstallObservedItem $Item $Context $Mode }
        $Selected[$Id] = $Item
        foreach ($Dependency in ([string]$Item.depends_on).Split(' ')) {
            if (-not $Dependency) { continue }
            if ($Item.action -eq 'skip' -and $Dependency -cin ([string]$Item.install_depends_on).Split(' ')) { continue }
            $Pending.Enqueue($Dependency)
        }
    }
    foreach ($Item in $Plan) { if ($Selected.ContainsKey($Item.id)) { $Selected[$Item.id] } }
}

function Get-WorkflowComponents {
    param([hashtable]$Profile, [object[]]$Plan, [object[]]$ApplyItems)
    foreach ($Pair in $Profile.components.Split(' ')) {
        $Component, $Id = $Pair.Split(':')
        $Item = @($Plan | Where-Object { $_.id -ceq $Id })
        if ($Item.Count -ne 1) { throw "Component $Component requires unknown install item $Id" }
        if ($Item[0].reason -like 'environment-not-selected:*' -or $Item[0].reason -like 'provided-by-host:*') { throw "Component $Component requires excluded install item $Id" }
        if (-not @($ApplyItems | Where-Object { $_.id -ceq $Component }).Count) { throw "Unknown apply component $Component" }
        $Component
    }
}
