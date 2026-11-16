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

function Get-WorkflowGitConfigPaths {
    if ($env:GIT_CONFIG_GLOBAL) { [IO.Path]::GetFullPath($env:GIT_CONFIG_GLOBAL); return }
    $GitHome = if ($env:HOME) { $env:HOME } elseif ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    [IO.Path]::GetFullPath((Join-Path $GitHome '.gitconfig'))
    $XdgRoot = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $GitHome '.config' }
    [IO.Path]::GetFullPath((Join-Path $XdgRoot 'git/config'))
}

# WSL owns its interpreter selection; never export the host interpreter to it.
function Invoke-WorkflowGuestCommand {
    param([scriptblock]$Action)
    Initialize-DotfilesPython
    $SavedPython = $env:DOTFILES_PYTHON
    try {
        Remove-Item Env:DOTFILES_PYTHON -ErrorAction SilentlyContinue
        & $Action
    } finally {
        if ($null -eq $SavedPython) { Remove-Item Env:DOTFILES_PYTHON -ErrorAction SilentlyContinue }
        else { $env:DOTFILES_PYTHON = $SavedPython }
    }
}

function Get-WorkflowWslPlan {
    param([string]$RepoRoot, [string]$Distribution, [bool]$NoChinaMirrors, [string]$SessionId, [bool]$RecordReports = $false, [string]$GuestProfile = 'wsl-full')
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'WSL is required; initialize the declared WSL2 distribution first.' }
    $Prefix = "\\wsl.localhost\$Distribution\"
    $LegacyPrefix = "\\wsl`$\$Distribution\"
    if ($RepoRoot.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) {
        $LinuxRoot = '/' + $RepoRoot.Substring($Prefix.Length).Replace('\', '/')
    } elseif ($RepoRoot.StartsWith($LegacyPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $LinuxRoot = '/' + $RepoRoot.Substring($LegacyPrefix.Length).Replace('\', '/')
    } else { throw "Checkout must be inside '$Distribution', for example $Prefix`home\<user>\dotfiles." }
    $Rows = @(Invoke-WorkflowGuestCommand { Invoke-InstallProbe wsl.exe @('--list', '--verbose') })
    $Version = @($Rows | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -match "^\*?\s*$([Regex]::Escape($Distribution))\s+.*\s+2$" })
    if (-not $Version.Count) { throw "WSL distribution '$Distribution' must exist and use WSL2." }
    # Pass paths as arguments, never interpolate them into shell source text.
    $Installer = "$LinuxRoot/install/linux.sh"
    Invoke-WorkflowGuestCommand { Invoke-InstallProbe wsl.exe @('-d', $Distribution, '--', 'test', '-f', $Installer) } | Out-Null
    $Arguments = @('-d', $Distribution, '--', 'bash', $Installer, '--yes', '--profile', $GuestProfile, '--session-id', $SessionId)
    if ($NoChinaMirrors) { $Arguments += '--no-china-mirrors' } else { $Arguments += '--china-mirrors' }
    $HostReport = ''
    if ($RecordReports) {
        $LinuxHome = @(Invoke-WorkflowGuestCommand { Invoke-InstallProbe wsl.exe @('-d', $Distribution, '--', 'printenv', 'HOME') })
        if ($LinuxHome.Count -ne 1 -or $LinuxHome[0] -notmatch '^/[^|\r\n\t]+$') { throw 'Could not resolve WSL report destination' }
        $GuestReport = "$($LinuxHome[0])/.dotfiles-workflow-$SessionId.tsv"
        $HostReport = "\\wsl.localhost\$Distribution" + $GuestReport.Replace('/', '\')
        $Arguments += @('--results', $GuestReport)
    }
    $Text = @(Invoke-WorkflowGuestCommand { Invoke-InstallProbe wsl.exe ($Arguments + @('--plan')) })
    @{ Arguments = $Arguments; Text = $Text; HostReport = $HostReport }
}

. (Join-Path $PSScriptRoot 'execution-result.ps1')
. (Join-Path $PSScriptRoot 'workflow-session.ps1')
. (Join-Path $PSScriptRoot 'workflow-review.ps1')
. (Join-Path $PSScriptRoot 'plan-explain.ps1')

. (Join-Path $PSScriptRoot 'workflow-windows.ps1')
