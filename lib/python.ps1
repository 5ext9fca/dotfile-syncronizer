$DotfilesPythonLauncher = Join-Path $PSScriptRoot '../dotfiles_core/launch.py'

function Initialize-DotfilesPython {
    if ($script:DotfilesPythonExecutable) { return }
    $Selected = if (Test-Path Env:DOTFILES_PYTHON) { $env:DOTFILES_PYTHON } elseif ($env:OS -eq 'Windows_NT') {
        Join-Path $PSScriptRoot '../.venv/Scripts/python.exe'
    } else { Join-Path $PSScriptRoot '../.venv/bin/python' }
    if (-not $Selected) { throw 'DOTFILES_PYTHON must name one interpreter' }
    $Resolved = Get-Command -Name $Selected -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $Resolved) { throw "Python interpreter unavailable: $Selected" }
    $Executable = [IO.Path]::GetFullPath($Resolved.Source)
    & $Executable -B $DotfilesPythonLauncher runtime-check | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Python >=3.15 and declared dependencies must be prepared before invocation' }
    $script:DotfilesPythonExecutable = $Executable
}

function Invoke-DotfilesPython {
    param([string[]]$Arguments)
    Initialize-DotfilesPython
    & $script:DotfilesPythonExecutable -B $DotfilesPythonLauncher @Arguments
}
