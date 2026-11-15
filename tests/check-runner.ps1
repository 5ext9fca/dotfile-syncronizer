$ErrorActionPreference = 'Stop'
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-check-tests-' + [guid]::NewGuid().ToString('N'))
$Saved = $env:DOTFILES_TEST_POWERSHELL
$PowerShell = (Get-Process -Id $PID).Path
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $Temp 'tests/checks')
    Copy-Item (Join-Path $PSScriptRoot 'check.ps1') (Join-Path $Temp 'tests/check.ps1')
    'exit 19' | Set-Content (Join-Path $Temp 'tests/fail.ps1')
    'Write-Output continued' | Set-Content (Join-Path $Temp 'tests/pass.ps1')
    @("first`tcore`tlinux macos windows`tpowershell`ttests/fail.ps1`t-",
      "second`tcore`tlinux macos windows`tpowershell`ttests/pass.ps1`t-",
      "foreign`tcore`tother`tpowershell`tnot-present`t-") | Set-Content (Join-Path $Temp 'tests/checks/manifest.tsv')
    $env:DOTFILES_TEST_POWERSHELL = $PowerShell
    $Output = @(& $PowerShell -NoProfile -File (Join-Path $Temp 'tests/check.ps1') -Strict) -join "`n"
    Assert ($LASTEXITCODE -eq 1) 'Runner swallowed check failure'
    Assert ($Output.Contains('FAIL first: exit 19') -and $Output.Contains('PASS second')) 'Runner did not continue after failure'
    Assert ($Output.Contains('passed=1 failed=1 skipped=1')) 'Incorrect failure summary'
    $env:DOTFILES_TEST_POWERSHELL = Join-Path $Temp 'missing-executable'
    $Output = @(& $PowerShell -NoProfile -File (Join-Path $Temp 'tests/check.ps1')) -join "`n"
    Assert ($LASTEXITCODE -eq 0 -and $Output.Contains('passed=0 failed=0 skipped=3')) 'Missing runtime was not explicitly skipped'
    $Output = @(& $PowerShell -NoProfile -File (Join-Path $Temp 'tests/check.ps1') -Strict) -join "`n"
    Assert ($LASTEXITCODE -eq 1 -and $Output.Contains('passed=0 failed=2 skipped=1')) 'Strict mode accepted a missing runtime'
    Write-Host 'Unified PowerShell check runner failure, continuation and missing-runtime tests passed.'
} finally {
    $env:DOTFILES_TEST_POWERSHELL = $Saved
    Remove-Item -LiteralPath $Temp -Recurse -Force
}
