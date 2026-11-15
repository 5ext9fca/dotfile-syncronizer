function Write-AtomicReport {
    param([string]$Path, [string]$Text, [switch]$CreateNew)
    $ErrorActionPreference = 'Stop'
    $Temporary = "$Path.tmp.$([guid]::NewGuid().ToString('N'))"
    $Stream = $null
    try {
        $Stream = [IO.File]::Open($Temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $Bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        $Stream.Write($Bytes, 0, $Bytes.Length)
        $Stream.Flush($true)
        $Stream.Dispose(); $Stream = $null
        if ($CreateNew -or -not [IO.File]::Exists($Path)) {
            [IO.File]::Move($Temporary, $Path)
        } else {
            # File.Replace is atomic on the same volume (unlike delete + move).
            [IO.File]::Replace($Temporary, $Path, [System.Management.Automation.Language.NullString]::Value)
        }
    } finally {
        if ($Stream) { $Stream.Dispose() }
        if ([IO.File]::Exists($Temporary)) { [IO.File]::Delete($Temporary) }
    }
}
