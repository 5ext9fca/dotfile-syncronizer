# Stage selection, reporting, and WSL inspection for Windows PowerShell 5.1+.
. (Join-Path $PSScriptRoot 'workflow-profile.ps1')

# Definitions and handlers are loaded once; the caller supplies all run state.
. (Join-Path $PSScriptRoot 'workflow-stages.ps1')
. (Join-Path $PSScriptRoot 'install-items.ps1')
. (Join-Path $PSScriptRoot 'apply-items.ps1')

function Get-WorkflowStages {
    param([string]$OnlyStage, [string]$FromStage)
    return ,@(Get-WorkflowStagePlan windows @{} $OnlyStage $FromStage | Where-Object { $_.Enabled } | ForEach-Object { $_.Id })
}

function Assert-WorkflowOutput {
    param([string]$Path, [string[]]$ProtectedRoots)
    if (Get-ApplyEntry $Path) { throw "Workflow output already exists: $Path" }
    if ($Path -match '[|\r\n\t]') { throw 'Invalid workflow output path' }
    foreach ($Root in $ProtectedRoots) {
        if ((Test-ApplyWithin $Path $Root) -or (Test-ApplyWithin $Root $Path)) { throw "Workflow output overlaps repository or configuration: $Path" }
    }
    $Parent = Resolve-ApplyRoot (Split-Path -Parent $Path)
    while (-not (Get-ApplyEntry $Parent)) { $Parent = Split-Path -Parent $Parent }
    $Entry = Get-ApplyEntry $Parent
    if (-not $Entry.PSIsContainer) { throw "Workflow output parent is not a directory: $Parent" }
}

function Get-WorkflowGitConfigPaths {
    if ($env:GIT_CONFIG_GLOBAL) { [IO.Path]::GetFullPath($env:GIT_CONFIG_GLOBAL); return }
    $GitHome = if ($env:HOME) { $env:HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    [IO.Path]::GetFullPath((Join-Path $GitHome '.gitconfig'))
    $XdgRoot = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $GitHome '.config' }
    [IO.Path]::GetFullPath((Join-Path $XdgRoot 'git/config'))
}

function Get-WorkflowWslPlan {
    param([string]$RepoRoot, [string]$Distribution, [bool]$NoChinaMirrors, [string]$SessionId, [bool]$RecordReports = $false)
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'WSL is required; initialize the declared WSL2 distribution first.' }
    $Prefix = "\\wsl.localhost\$Distribution\"
    $LegacyPrefix = "\\wsl`$\$Distribution\"
    if ($RepoRoot.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) {
        $LinuxRoot = '/' + $RepoRoot.Substring($Prefix.Length).Replace('\', '/')
    } elseif ($RepoRoot.StartsWith($LegacyPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $LinuxRoot = '/' + $RepoRoot.Substring($LegacyPrefix.Length).Replace('\', '/')
    } else { throw "Checkout must be inside '$Distribution', for example $Prefix`home\<user>\dotfiles." }
    $Rows = @(Invoke-InstallProbe wsl.exe @('--list', '--verbose'))
    $Version = @($Rows | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -match "^\*?\s*$([Regex]::Escape($Distribution))\s+.*\s+2$" })
    if (-not $Version.Count) { throw "WSL distribution '$Distribution' must exist and use WSL2." }
    # Pass paths as arguments, never interpolate them into shell source text.
    Invoke-InstallProbe wsl.exe @('-d', $Distribution, '--', 'test', '-f', '/etc/fedora-release') | Out-Null
    $Installer = "$LinuxRoot/install/linux.sh"
    Invoke-InstallProbe wsl.exe @('-d', $Distribution, '--', 'test', '-f', $Installer) | Out-Null
    $Arguments = @('-d', $Distribution, '--', 'bash', $Installer, '--yes', '--session-id', $SessionId)
    if ($NoChinaMirrors) { $Arguments += '--no-china-mirrors' }
    $HostReport = ''
    if ($RecordReports) {
        $LinuxHome = @(Invoke-InstallProbe wsl.exe @('-d', $Distribution, '--', 'printenv', 'HOME'))
        if ($LinuxHome.Count -ne 1 -or $LinuxHome[0] -notmatch '^/[^|\r\n\t]+$') { throw 'Could not resolve WSL report destination' }
        $GuestReport = "$($LinuxHome[0])/.dotfiles-workflow-$SessionId.tsv"
        $HostReport = "\\wsl.localhost\$Distribution" + $GuestReport.Replace('/', '\')
        $Arguments += @('--results', $GuestReport)
    }
    $Text = @(Invoke-InstallProbe wsl.exe ($Arguments + @('--plan')))
    @{ Arguments = $Arguments; Text = $Text; HostReport = $HostReport }
}

. (Join-Path $PSScriptRoot 'execution-result.ps1')
. (Join-Path $PSScriptRoot 'workflow-session.ps1')
. (Join-Path $PSScriptRoot 'workflow-review.ps1')
. (Join-Path $PSScriptRoot 'plan-explain.ps1')

. (Join-Path $PSScriptRoot 'workflow-windows.ps1')
