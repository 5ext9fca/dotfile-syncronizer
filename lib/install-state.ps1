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
    if ($Item.method -eq 'font-download') {
        $Directory = Join-Path $env:LOCALAPPDATA "Microsoft/Windows/Fonts/$($Item.id)"
        $Fonts = Get-Item 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue
        foreach ($File in $Item.font_files.Split(' ')) {
            $Path = Join-Path $Directory $File
            $Name = Get-WindowsFontRegistryName $File
            if (-not $Fonts -or $Fonts.GetValue($Name) -ne $Path -or -not [IO.File]::Exists($Path)) { return '' }
        }
        return 'present'
    }
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

function Get-NativeInstallState {
    param([hashtable]$Item, [hashtable]$Context)
    $State = Get-WindowsItemState $Item $Context
    if (-not $State -and $Item.method -eq 'winget' -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        $Probe = Invoke-ManagedCommand probe winget.exe @('list', '--id', $Item.packages, '--exact', '--source', $Item.source_repo, '--accept-source-agreements', '--disable-interactivity') -TimeoutSeconds (Get-InstallExecutionPolicy winget probe).TimeoutSeconds
        # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND (0x8A150014) is absence; other errors must propagate.
        if ($Probe.ExitCode -notin @(0, -1978335212)) { throw (New-ExecutionException 'Installation presence probe failed' $Probe.ExitCode) }
        if ($Probe.ExitCode -eq 0 -and $Probe.Stdout -match [regex]::Escape($Item.packages)) { $State = 'present' }
    }
    [string]$State
}

function Get-InstallObservedItem {
    param([hashtable]$Item, [hashtable]$Context, [ValidateSet('normal', 'resume')][string]$Mode)
    $Value = Invoke-DotfilesRequest install-observe-native @{
        style='windows'; native_shell=(Get-Process -Id $PID).Path; item=$Item; native_context=$Context;
        mode=$Mode; policy_path=[string]$script:DotfilesExecutionPolicyPath
    }
    ConvertTo-DotfilesRecord $Value
}

function Get-WindowsResumeItem {
    param([hashtable]$Item, [hashtable]$Context)
    Get-InstallObservedItem $Item $Context resume
}
