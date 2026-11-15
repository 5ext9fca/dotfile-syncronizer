$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/deployment-lock.ps1')
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-lock-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$OldPath = $env:DOTFILES_DEPLOYMENT_LOCK; $OldToken = $env:DOTFILES_DEPLOYMENT_TOKEN
$env:DOTFILES_DEPLOYMENT_LOCK = Join-Path $Temp 'lock'; $env:DOTFILES_DEPLOYMENT_TOKEN = $null
try {
    Invoke-DeploymentLocked $false {
        if (-not (Test-Path $env:DOTFILES_DEPLOYMENT_LOCK)) { throw 'Lease missing' }
        Invoke-DeploymentLocked $false { [IO.File]::WriteAllText((Join-Path $Temp 'nested'), 'nested') }
        $Token = $env:DOTFILES_DEPLOYMENT_TOKEN; $env:DOTFILES_DEPLOYMENT_TOKEN = $null
        try {
            $Rejected = $false
            try { Invoke-DeploymentLocked $false { throw 'Unexpected entry' } } catch { $Rejected = $_.Exception.Message -like 'Deployment lock exists:*' }
            if (-not $Rejected) { throw 'Second owner was not rejected' }
            Invoke-DeploymentLocked $true { [IO.File]::WriteAllText((Join-Path $Temp 'dry'), 'dry') }
        } finally { $env:DOTFILES_DEPLOYMENT_TOKEN = $Token }
    }
    if (Test-Path $env:DOTFILES_DEPLOYMENT_LOCK) { throw 'Lease not released' }
    try { Invoke-DeploymentLocked $false { throw 'Failed operation' } } catch { }
    if (Test-Path $env:DOTFILES_DEPLOYMENT_LOCK) { throw 'Failed operation retained lease' }
    $null = New-Item -ItemType Directory $env:DOTFILES_DEPLOYMENT_LOCK
    [IO.File]::WriteAllText((Join-Path $env:DOTFILES_DEPLOYMENT_LOCK 'owner'), '999999|unknown|token')
    $Rejected = $false
    try { Invoke-DeploymentLocked $false { } } catch { $Rejected = $true }
    if (-not $Rejected -or -not (Test-Path $env:DOTFILES_DEPLOYMENT_LOCK)) { throw 'Stale lease was reclaimed' }
} finally {
    $env:DOTFILES_DEPLOYMENT_LOCK = $OldPath; $env:DOTFILES_DEPLOYMENT_TOKEN = $OldToken
    Remove-Item $Temp -Recurse -Force
}
Write-Host 'Deployment contention, nesting, read-only bypass and failure cleanup passed.'
