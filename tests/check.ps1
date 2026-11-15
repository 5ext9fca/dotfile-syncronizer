[CmdletBinding()]
param(
    [ValidateSet('core', 'cross', 'dry-run', 'lint', 'all')] [string]$Suite = 'core',
    [switch]$Strict,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$CurrentHost = if ($env:OS -eq 'Windows_NT') { 'windows' } elseif ((& uname -s) -eq 'Darwin') { 'macos' } else { 'linux' }
$Bash = if ($env:DOTFILES_TEST_BASH) { $env:DOTFILES_TEST_BASH } else { 'bash' }
$PowerShell = if ($env:DOTFILES_TEST_POWERSHELL) { $env:DOTFILES_TEST_POWERSHELL } else { (Get-Process -Id $PID).Path }
$Python = if ($env:DOTFILES_TEST_PYTHON) { $env:DOTFILES_TEST_PYTHON } elseif ($CurrentHost -eq 'windows') { 'python' } else { 'python3' }
function Invoke-CheckCommand {
    param([string]$Command, [string[]]$Arguments, [switch]$Quiet)
    # Windows PowerShell represents native stderr as ErrorRecords; the child's
    # exit code, not stderr alone, determines whether the check failed.
    $ErrorActionPreference = 'Continue'
    if ($Quiet) { & $Command @Arguments 2>$null | Out-Null }
    else { & $Command @Arguments | Out-Host }
    return $LASTEXITCODE
}
$Passed = 0; $Failed = 0; $Skipped = 0
Push-Location $RepoRoot
try {
    foreach ($Line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checks/manifest.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Id, $Group, $Hosts, $Runtime, $Entry, $Arguments = $Line.Split("`t")
        if ($Suite -ne 'all' -and $Suite -ne $Group) { continue }
        if ($CurrentHost -notin $Hosts.Split(' ')) { Write-Host "SKIP ${Id}: host $CurrentHost is outside [$Hosts]"; $Skipped++; continue }
        if ($List) { Write-Output "$Id`t$Group`t$Runtime`t$Entry"; continue }
        $Missing = ''; $Command = ''; $CommandArguments = @()
        switch ($Runtime) {
            'bash' { $Command = $Bash; $CommandArguments = @($Entry) }
            'powershell' { $Command = $PowerShell; $CommandArguments = @('-NoProfile', '-File', $Entry) }
            'python' { $Command = $Python; $CommandArguments = if (Test-Path -LiteralPath $Entry -PathType Leaf) { @('-B', $Entry) } else { @('-B', '-m', 'unittest', 'discover', '-s', $Entry, '-p', 'test_*.py') } }
            default { throw "Unknown check runtime $Runtime" }
        }
        if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { $Missing = "runtime $Command" }
        if ($Runtime -eq 'python' -and -not $Missing) {
            $Code = Invoke-CheckCommand $Python @('-c', 'import sys; assert sys.version_info >= (3, 11)') -Quiet
            if ($Code -ne 0) { $Missing = 'Python >=3.11' }
        }
        if ($Id -eq 'install-parity' -and -not (Get-Command $Bash -ErrorAction SilentlyContinue)) { $Missing = "Bash $Bash" }
        if ($Id -eq 'shell-lint') {
            $ShellCheck = if ($env:DOTFILES_TEST_SHELLCHECK) { $env:DOTFILES_TEST_SHELLCHECK } else { 'shellcheck' }
            if (-not (Get-Command $ShellCheck -ErrorAction SilentlyContinue)) { $Missing = 'ShellCheck' }
        }
        if ($Missing) {
            if ($Strict) { Write-Host "FAIL ${Id}: missing $Missing"; $Failed++ }
            else { Write-Host "SKIP ${Id}: missing $Missing"; $Skipped++ }
            continue
        }
        if ($Arguments -ne '-') { $CommandArguments += $Arguments.Split(' ') }
        if ($Id -eq 'install-parity') { $CommandArguments += @('-Bash', $Bash) }
        Write-Host "RUN $Id"
        $Code = Invoke-CheckCommand $Command $CommandArguments
        if ($Code -eq 0) { Write-Host "PASS $Id"; $Passed++ }
        else { Write-Host "FAIL ${Id}: exit $Code"; $Failed++ }
    }
} finally { Pop-Location }
Write-Host "Checks: passed=$Passed failed=$Failed skipped=$Skipped"
if ($Failed) { exit 1 }
exit 0
