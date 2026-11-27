[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Platform,
    [string]$Items,
    [switch]$NoChinaMirrors,
    [switch]$Explain,
    [switch]$Wsl
)
$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('Items')) { $Items = Join-Path $PSScriptRoot '../software/items' }
. (Join-Path $PSScriptRoot '../lib/install-items.ps1')
. (Join-Path $PSScriptRoot '../lib/plan-explain.ps1')
Initialize-DotfilesPython
$Plan = @(Get-InstallPlan -Directory $Items -Platform $Platform -Mirrors (-not $NoChinaMirrors) -Wsl ([bool]$Wsl) -Inspect $false)
if ($Explain) { Show-InstallPlanExplanation $Plan $Platform all $Items }
else { ConvertTo-InstallPlanText -Plan $Plan -Envelope }
