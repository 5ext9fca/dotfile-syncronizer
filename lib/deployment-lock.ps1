function Invoke-DeploymentLocked {
    param([bool]$DryRun, [scriptblock]$Action)
    if ($DryRun) { & $Action; return }
    $Path = $env:DOTFILES_DEPLOYMENT_LOCK
    if (-not $Path) {
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            $Path = Join-Path ([IO.Path]::GetTempPath()) 'dotfiles-deployment.lock'
        } else {
            $UserId = & id -u
            if ($LASTEXITCODE -ne 0) { throw 'Could not determine deployment lock owner' }
            $Path = Join-Path ([IO.Path]::GetTempPath()) "dotfiles-deployment-$UserId.lock"
        }
    }
    $OwnerPath = Join-Path $Path 'owner'
    $Existing = if (Test-Path -LiteralPath $OwnerPath -PathType Leaf) { [IO.File]::ReadAllText($OwnerPath).TrimEnd("`r", "`n") } else { '' }
    if ($env:DOTFILES_DEPLOYMENT_TOKEN -and $Existing.Split('|')[-1] -ceq $env:DOTFILES_DEPLOYMENT_TOKEN) { & $Action; return }
    try { $null = New-Item -ItemType Directory -Path $Path -ErrorAction Stop }
    catch { throw "Deployment lock exists: $Path. Owner: $Existing. Stop all related writers before recovery; never remove stale locks automatically." }
    $Token = [guid]::NewGuid().ToString('N')
    $Owner = "$PID|$([Environment]::MachineName)|$Token"
    $OldPath = $env:DOTFILES_DEPLOYMENT_LOCK; $OldToken = $env:DOTFILES_DEPLOYMENT_TOKEN
    try {
        [IO.File]::WriteAllText($OwnerPath, $Owner, [Text.UTF8Encoding]::new($false))
        $env:DOTFILES_DEPLOYMENT_LOCK = $Path; $env:DOTFILES_DEPLOYMENT_TOKEN = $Token
        & $Action
    } finally {
        $env:DOTFILES_DEPLOYMENT_LOCK = $OldPath; $env:DOTFILES_DEPLOYMENT_TOKEN = $OldToken
        if ([IO.File]::Exists($OwnerPath) -and [IO.File]::ReadAllText($OwnerPath) -ceq $Owner) {
            [IO.File]::Delete($OwnerPath); [IO.Directory]::Delete($Path, $false)
        }
    }
}
