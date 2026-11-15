$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/atomic-report.ps1')
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-atomic-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
try {
    $Path = Join-Path $Temp 'report'
    Write-AtomicReport $Path 'old' -CreateNew
    $Reader = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        Write-AtomicReport $Path 'new'
        $TextReader = [IO.StreamReader]::new($Reader)
        if ($TextReader.ReadToEnd() -ne 'old' -or [IO.File]::ReadAllText($Path) -ne 'new') { throw 'Reader saw an incomplete snapshot' }
    } finally { $Reader.Dispose() }
    $Rejected = $false
    try { Write-AtomicReport $Path 'bad' -CreateNew } catch { $Rejected = $true }
    if (-not $Rejected -or [IO.File]::ReadAllText($Path) -ne 'new') { throw 'Exclusive publication replaced an existing report' }
    $Directory = Join-Path $Temp 'directory'; $null = New-Item -ItemType Directory $Directory
    $Rejected = $false
    try { Write-AtomicReport $Directory 'bad' } catch { $Rejected = $true }
    if (-not $Rejected -or @(Get-ChildItem $Temp -Filter '*.tmp.*').Count) { throw 'Failed publication retained temporary files' }
} finally { Remove-Item $Temp -Recurse -Force }
Write-Host 'Atomic report replacement, failed publication and exclusive publication passed.'
