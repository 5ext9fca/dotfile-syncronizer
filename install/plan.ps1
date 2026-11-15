[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Platform,
    [string]$Items = (Join-Path $PSScriptRoot 'items'),
    [switch]$NoChinaMirrors,
    [switch]$Explain,
    [switch]$Wsl
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/install-items.ps1')
. (Join-Path $PSScriptRoot '../lib/plan-explain.ps1')
$Plan = @(Get-InstallPlan -Directory $Items -Platform $Platform -Mirrors (-not $NoChinaMirrors) -Wsl ([bool]$Wsl) -Inspect $false)
if ($Explain) { Show-InstallPlanExplanation $Plan $Platform all $Items }
else { ConvertTo-InstallPlanText -Plan $Plan -Envelope }
