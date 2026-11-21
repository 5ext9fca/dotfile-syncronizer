function Get-WindowsFontRegistryName {
    param([string]$File)
    $Format = if ([IO.Path]::GetExtension($File) -eq '.ttf') { 'TrueType' } else { 'OpenType' }
    return ([IO.Path]::GetFileNameWithoutExtension($File) + " ($Format)")
}

function Install-WindowsFontItem {
    param([hashtable]$Item, [hashtable]$Context)
    Invoke-InstallCommand -Context $Context -Method 'font-download' -Command 'powershell.exe' -Arguments @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
        (Join-Path $PSScriptRoot 'windows-fonts.ps1'), '-Id', $Item.id,
        '-SourceUrl', $Item.source_url, '-FontFiles', $Item.font_files, '-FontFamily', $Item.font_family
    )
}

function Install-WinGetItem {
    param([hashtable]$Item, [hashtable]$Context)
    Invoke-InstallCommand -Context $Context -Command 'winget.exe' -Arguments @(
        'install', '--id', $Item.packages, '--exact', '--source', $Item.source_repo,
        '--accept-package-agreements', '--accept-source-agreements'
    )
}

function Install-MsvcItem {
    param([hashtable]$Item, [hashtable]$Context)
    if ($Item.state.StartsWith('modify:', [StringComparison]::Ordinal)) {
        $VsSetup = Join-Path $Context.VsInstallerRoot 'setup.exe'
        if (-not $Context.DryRun -and -not (Test-Path -LiteralPath $VsSetup)) { throw "Missing Visual Studio Installer: $VsSetup" }
        Invoke-InstallCommand -Context $Context -Command $VsSetup -Arguments @(
            'modify', '--installPath', $Item.state.Substring(7), '--add', $Item.workload,
            '--includeRecommended', '--passive', '--norestart'
        ) -Method msvc -Operation modify
    } else {
        Invoke-InstallCommand -Context $Context -Command 'winget.exe' -Arguments @(
            'install', '--id', $Item.packages, '--exact', '--source', $Item.source_repo,
            '--override', "--passive --wait --add $($Item.workload) --includeRecommended --norestart",
            '--accept-package-agreements', '--accept-source-agreements'
        )
    }
}
