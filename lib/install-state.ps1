function Invoke-InstallProbe {
    param([string]$Command, [object[]]$Arguments, [string]$Method = '*')
    $Policy = Get-InstallExecutionPolicy $Method probe
    $Result = Invoke-ManagedCommand probe $Command $Arguments -TimeoutSeconds $Policy.TimeoutSeconds
    if ($Result.ExitCode -ne 0) { throw (New-ExecutionException "Probe $Command failed with exit code $($Result.ExitCode)" $Result.ExitCode) }
    if ($Result.Stdout.Length) { $Result.Stdout.TrimEnd("`r", "`n") -split '\r?\n' }
}

function Get-WindowsItemState {
    param([hashtable]$Item, [hashtable]$Context)
    if ($Item.discovery) { return Get-InstallDiscoveryState $Item $Context }
    if ($Item.probe_command -and (Get-Command $Item.probe_command -ErrorAction SilentlyContinue)) { return 'present' }
    if ($Item.method -eq 'msvc') {
        $VsWhere = Join-Path $Context.VsInstallerRoot 'vswhere.exe'
        if (Test-Path -LiteralPath $VsWhere) {
            $Installed = @(Invoke-InstallProbe -Method msvc -Command $VsWhere -Arguments @('-products', '*', '-requires', $Item.components, '-latest', '-property', 'installationPath'))
            if ($Installed.Count -gt 0 -and $Installed[0]) { return 'present' }
            $BuildTools = @(Invoke-InstallProbe -Method msvc -Command $VsWhere -Arguments @('-products', 'Microsoft.VisualStudio.Product.BuildTools', '-latest', '-property', 'installationPath'))
            if ($BuildTools.Count -gt 0 -and $BuildTools[0]) { return "modify:$($BuildTools[0])" }
        }
    }
    return ''
}

function Get-InstallObservedItem {
    param([hashtable]$Item, [hashtable]$Context, [ValidateSet('normal', 'resume')][string]$Mode)
    $Fresh = $Item.Clone()
    if ($Item.reason -match '^(provided-by-host:|environment-not-selected:)') { return $Fresh }
    $Fresh.detected_method = ''; $Fresh.detected_paths = ''
    if ($Fresh.discovery) {
        $Observation = Get-InstallDiscoveryObservation $Fresh $Context
        $Fresh.state = $Observation.State; $Fresh.detected_method = $Observation.Method; $Fresh.detected_paths = $Observation.Paths
    } else { $Fresh.state = Get-WindowsItemState $Fresh $Context }
    if (-not $Fresh.discovery -and -not $Fresh.state -and $Fresh.method -eq 'winget' -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        $Probe = Invoke-ManagedCommand probe winget.exe @('list', '--id', $Fresh.packages, '--exact', '--source', $Fresh.source_repo, '--accept-source-agreements', '--disable-interactivity') -TimeoutSeconds (Get-InstallExecutionPolicy winget probe).TimeoutSeconds
        # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND (0x8A150014) is absence; other errors must propagate.
        if ($Probe.ExitCode -notin @(0, -1978335212)) { throw (New-ExecutionException 'Installation presence probe failed' $Probe.ExitCode) }
        if ($Probe.ExitCode -eq 0 -and $Probe.Stdout -match [regex]::Escape($Fresh.packages)) { $Fresh.state = 'present' }
    }
    $Decision = Get-InstallDecision $Fresh.state $Mode ([bool]$Fresh.discovery)
    $Fresh.decision_reason = $Decision.DecisionReason
    $Fresh.state = $Decision.State; $Fresh.action = $Decision.Action; $Fresh.reason = $Decision.Reason
    $Fresh
}

function Get-WindowsResumeItem {
    param([hashtable]$Item, [hashtable]$Context)
    Get-InstallObservedItem $Item $Context resume
}
