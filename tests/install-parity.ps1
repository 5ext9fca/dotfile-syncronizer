param([string]$Bash = 'bash')
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/install-items.ps1')
Push-Location $RepoRoot
try {
    foreach ($Platform in @('linux.apt', 'linux.dnf', 'linux.pacman', 'macos', 'windows')) {
        foreach ($Mirrors in @($true, $false)) {
            foreach ($Wsl in @($true, $false)) {
                $Arguments = @('install/plan.sh', '--platform', $Platform)
                if (-not $Mirrors) { $Arguments += '--no-china-mirrors' }
                if ($Wsl) { $Arguments += '--wsl' }
                $BashPlan = @(& $Bash @Arguments)
                if ($LASTEXITCODE -ne 0) { throw "Bash planner failed on $Platform" }
                $Plan = @(Get-InstallPlan -Directory (Join-Path $RepoRoot 'install/items') -Platform $Platform -Mirrors $Mirrors -Wsl $Wsl -Inspect $false)
                $PowerShellPlan = @(ConvertTo-InstallPlanText -Plan $Plan -Envelope)
                if (($BashPlan -join "`n") -cne ($PowerShellPlan -join "`n")) { throw "Planner mismatch: $Platform mirrors=$Mirrors wsl=$Wsl" }
            }
        }
    }
    Write-Host 'Bash/PowerShell parity passed for 20 platform/source/scope combinations.'
} finally { Pop-Location }
