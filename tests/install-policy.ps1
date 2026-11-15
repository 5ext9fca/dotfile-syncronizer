$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/install-items.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
foreach ($Line in Get-Content (Join-Path $PSScriptRoot 'fixtures/install-policy/cases.tsv')) {
    $Name, $Expected = $Line.Split("`t")
    $Failed = $false
    try { $Policy = Get-InstallExecutionPolicy apt probe (Join-Path $PSScriptRoot "fixtures/install-policy/$Name.tsv") } catch { $Failed = $true }
    Assert ($Failed -eq ($Expected -eq 'invalid')) "Policy validation mismatch: $Name"
    if (-not $Failed) { Assert ($Policy.TimeoutSeconds -eq $(if ($Name -eq 'override') { 8 } else { 30 })) 'Wrong timeout' }
}
Assert ((Get-InstallExecutionPolicy homebrew download).TimeoutSeconds -eq 120) 'Wrong download policy'
$script:SeenTimeout = -1
function Invoke-ManagedCommand {
    param($Policy, $Command, $Arguments, $DryRun, $TimeoutSeconds, [switch]$Stream)
    $script:SeenTimeout = $TimeoutSeconds
    @{ExitCode=3010}
}
Invoke-InstallCommand @{DryRun=$false} example @() -Method msvc -Operation modify
Assert ($script:SeenTimeout -eq 0) 'Install wait policy changed'
$Failed=$false
try { Invoke-InstallCommand @{DryRun=$false} example @() -Method winget } catch { $Failed=$true }
Assert $Failed 'MSVC success code leaked into WinGet install'
'PowerShell execution policy and adapter tests passed.'
