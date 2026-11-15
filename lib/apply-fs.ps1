# Read-only filesystem inspection and stable identities.
function Get-ApplyEntry {
    param([string]$Path)
    Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}
function Test-ApplyLink {
    param($Entry)
    $null -ne $Entry -and [bool]($Entry.Attributes -band [IO.FileAttributes]::ReparsePoint)
}
function Test-ApplyWithin {
    param([string]$Path, [string]$Root)
    $Path = [IO.Path]::GetFullPath($Path); $Root = [IO.Path]::GetFullPath($Root)
    $Path.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Get-ApplyTree {
    param([string]$Path)
    $Entries = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
    foreach ($Entry in $Entries) {
        if ($Entry.FullName -match '[|\t\r\n]') { throw 'Unsupported path character' }
        $Entry
        if ($Entry.PSIsContainer -and -not (Test-ApplyLink $Entry)) { Get-ApplyTree $Entry.FullName }
    }
}
function Get-ApplyHash {
    param([string]$Text)
    $Sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($Sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() } finally { $Sha.Dispose() }
}
function Get-ApplyContent {
    param([string]$Path)
    $Entry = Get-ApplyEntry $Path
    if (-not $Entry) { return 'absent' }
    if (Test-ApplyLink $Entry) { return 'l:' + (Get-ApplyHash ([string]($Entry.Target -join '|'))) }
    if (-not $Entry.PSIsContainer) { return 'f:' + (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
    $Rows = @{}
    foreach ($Child in @(Get-ApplyTree $Path)) {
        $Relative = $Child.FullName.Substring($Path.Length).TrimStart('\', '/')
        if ($Child.PSIsContainer -and -not (Test-ApplyLink $Child)) { $Rows[$Relative] = 'd' }
        else { $Rows[$Relative] = Get-ApplyContent $Child.FullName }
    }
    [string[]]$Keys = @($Rows.Keys); [Array]::Sort($Keys, [StringComparer]::Ordinal)
    return 'd:' + (Get-ApplyHash (($Keys | ForEach-Object { "$_|$($Rows[$_])" }) -join "`n"))
}
function Get-ApplyIdentity {
    param([string]$Path)
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        if (-not ('DotfilesApplyFileId' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'apply-file-id.cs') }
        return [DotfilesApplyFileId]::Get($Path)
    }
    # Allows the same pure filesystem contracts to run under PowerShell on Unix.
    if ((& uname -s) -eq 'Darwin') { $Identity = & stat -f '%d-%i' $Path }
    else { $Identity = & stat -c '%d-%i' $Path }
    if ($LASTEXITCODE -ne 0) { throw "Cannot identify file: $Path" }
    $Identity
}
function Get-ApplyState {
    param([string]$Path)
    $Entry = Get-ApplyEntry $Path
    if (-not $Entry) { return 'absent' }
    return "$(Get-ApplyIdentity $Path):$(Get-ApplyContent $Path)"
}
function Resolve-ApplyRoot {
    param([string]$Path)
    if (-not $Path -or $Path -match '[|\t\r\n]') { throw 'Invalid deployment root' }
    $Path = [IO.Path]::GetFullPath($Path)
    if ($Path -ne [IO.Path]::GetPathRoot($Path)) { $Path = $Path.TrimEnd('\', '/') }
    $Probe = $Path
    while ($Probe) {
        $Entry = Get-ApplyEntry $Probe
        if ($Entry -and ((Test-ApplyLink $Entry) -or -not $Entry.PSIsContainer)) { throw "Root ancestor is not a real directory: $Probe" }
        $Parent = [IO.Path]::GetDirectoryName($Probe)
        if ($Parent -eq $Probe) { break }; $Probe = $Parent
    }
    $Path
}
function Get-ApplyAnchor {
    param([string]$Path)
    while (-not (Get-ApplyEntry $Path)) { $Path = [IO.Path]::GetDirectoryName($Path) }
    $Path
}
function Assert-ApplyParent {
    param([string]$Root, [string]$Target)
    if (-not (Test-ApplyWithin $Target $Root)) { throw 'Target is outside the deployment root' }
    $Probe = [IO.Path]::GetDirectoryName($Target)
    while (Test-ApplyWithin $Probe $Root) {
        $Entry = Get-ApplyEntry $Probe
        if (-not $Entry -or -not $Entry.PSIsContainer -or (Test-ApplyLink $Entry)) { throw "Unsafe deployment parent: $Probe" }
        if ($Probe -eq $Root) { break }; $Probe = [IO.Path]::GetDirectoryName($Probe)
    }
}
