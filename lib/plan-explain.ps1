function Show-InstallPlanExplanation {
    param([object[]]$Plan, [string]$Platform, [string]$Selection = 'all', [string]$Directory)
    Write-Output "Installation selection: $Selection; platform=$Platform"
    $Index = 0
    foreach ($Item in $Plan) {
        $Index++
        $SelectedBy = if ($Selection -eq 'all' -or $Item.id -cin $Selection.Split(' ')) { 'profile' } else { 'dependency' }
        $Dependencies = if ($Item.depends_on) { $Item.depends_on } else { 'none' }
        Write-Output "  $Index. $($Item.id): $($Item.action) ($($Item.reason)); selected-by=$SelectedBy, order=$($Item.order), method=$($Item.method)"
        Write-Output "     Packages: $($Item.packages); depends-on: $Dependencies"
        if ($Item.install_depends_on) { Write-Output "     Installation-only edges (omitted on skip unless independently selected): $($Item.install_depends_on)" }
        $Source = "     Source: $($Item.source_kind) ($($Item.source_origin))"
        if ($Item.source_url) { $Source += "; url=$($Item.source_url)" }
        if ($Item.source_repo) { $Source += "; repository=$($Item.source_repo)" }
        if ($Item.source_release) { $Source += "; release=$($Item.source_release)" }
        if (-not ($Item.source_url -or $Item.source_repo -or $Item.source_release)) { $Source += '; package-manager defaults' }
        Write-Output $Source
        if ($Item.discovery) {
            $Methods = if ($Item.methods) { $Item.methods } else { $Item.method }
            $Preferred = if ($Item.preferred_method) { $Item.preferred_method } else { $Item.method }
            Write-Output "     Discovery methods: $Methods; preferred install: $Preferred"
            Write-Output "     Required paths by method (file-system only): $($Item.discovery)"
        }
        if ($Item.state) { Write-Output "     Detected state: $($Item.state)" }
    }
    if ($Directory) {
        $Available = @(Read-InstallItems $Directory $Platform)
        foreach ($File in @(Get-ChildItem -LiteralPath $Directory -Filter '*.conf' | Sort-Object Name)) {
            if ($File.BaseName -cin @($Plan.id)) { continue }
            $Reason = if ($File.BaseName -cin @($Available.id)) { 'not-selected-by-profile' } else { 'platform-not-configured' }
            Write-Output "  $($File.BaseName): excluded ($Reason)"
        }
    }
    Write-Output 'Presence checks describe installation only; this plan is a current-state preview.'
}
function Show-ApplyPlanExplanation {
    param([object[]]$Plan)
    Write-Output 'Configuration effects:'
    foreach ($Item in $Plan) {
        Write-Output "  $($Item.Component): $($Item.Action) $($Item.Target) ($($Item.Reason))"
        if ($Item.Source -and $Item.Reason -ne 'excluded') { Write-Output "     Source: $($Item.Source)" }
        if ($Item.Backup) { Write-Output "     Existing target backup: $($Item.Backup)" }
    }
    Write-Output 'Unchanged/excluded targets and unmanaged files are preserved.'
}
