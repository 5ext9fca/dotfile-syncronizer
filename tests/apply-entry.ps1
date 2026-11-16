$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $Repo 'lib/python.ps1')
Initialize-DotfilesPython
# The cross-platform suite performs actual copy, backup, idempotence, archive
# independence and guarded recovery in a private HOME, using the public entry.
Invoke-DotfilesPython -Arguments @('runtime-check') | Out-Null
& $env:DOTFILES_PYTHON -B -m unittest discover -s (Join-Path $Repo 'tests/core') -p test_snapshot.py
if ($LASTEXITCODE -ne 0) { throw 'Snapshot apply entry integration failed' }
