. (Join-Path $PSScriptRoot 'python.ps1')
function Invoke-DeploymentLocked {
    param([bool]$DryRun, [scriptblock]$Action)
    Initialize-DotfilesPython
    $ViewerLeaseLibrary = & $env:DOTFILES_PYTHON -c 'from dotfile_viewer.install_config import ROOT; print(ROOT / "native/deployment-lock.ps1")'
    if ($LASTEXITCODE -ne 0) { throw 'dotfile-viewer is required' }
    . $ViewerLeaseLibrary
    Invoke-DeploymentLocked $DryRun $Action
}
