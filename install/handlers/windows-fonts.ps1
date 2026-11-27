param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]*$')][string]$Id,
    [Parameter(Mandatory)][ValidatePattern('^https://')][string]$SourceUrl,
    [Parameter(Mandatory)][string]$FontFiles,
    [Parameter(Mandatory)][string]$FontFamily
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows.ps1')
$Files = $FontFiles.Split(' ')
foreach ($File in $Files) {
    if ($File -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*\.(otf|ttf)$') { throw "Invalid font filename: $File" }
}
Add-Type -AssemblyName PresentationCore
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DotfilesFontResource {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResourceEx(string name, uint flags, IntPtr reserved);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wparam,
        IntPtr lparam, uint flags, uint timeout, out UIntPtr result);
}
'@
$Directory = Join-Path $env:LOCALAPPDATA "Microsoft/Windows/Fonts/$Id"
$Registry = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$Scratch = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-fonts-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Scratch)
try {
    $Paths = @{}
    foreach ($File in $Files) {
        $Path = Join-Path $Directory $File
        if (-not [IO.File]::Exists($Path)) {
            $Path = Join-Path $Scratch $File
            Invoke-WebRequest -UseBasicParsing -Uri ($SourceUrl.TrimEnd('/') + '/' + $File) -OutFile $Path -TimeoutSec 120
        }
        $Paths[$File] = $Path
    }
    # WPF caches the directory contents on first use. Validate the entire set before publishing.
    $Key = Get-Item -LiteralPath $Registry -ErrorAction SilentlyContinue
    foreach ($File in $Files) {
        $Font = [Windows.Media.GlyphTypeface]::new([Uri]$Paths[$File])
        if ($FontFamily -notin $Font.FamilyNames.Values) { throw "Expected $FontFamily in $File" }
        $Name = Get-WindowsFontRegistryName $File
        if ($Key -and $Key.GetValue($Name) -and $Key.GetValue($Name) -ne (Join-Path $Directory $File)) {
            throw "Font registry name already in use: $Name"
        }
    }
    [void][IO.Directory]::CreateDirectory($Directory)
    if (-not $Key) { New-Item -Path $Registry -Force | Out-Null }
    foreach ($File in $Files) {
        $Destination = Join-Path $Directory $File
        if ($Paths[$File] -ne $Destination) { [IO.File]::Copy($Paths[$File], $Destination) }
        if ([DotfilesFontResource]::AddFontResourceEx($Destination, 0, [IntPtr]::Zero) -eq 0) {
            throw "Could not load font: $File"
        }
        $Name = Get-WindowsFontRegistryName $File
        New-ItemProperty -LiteralPath $Registry -Name $Name -Value $Destination -PropertyType String -Force | Out-Null
    }
    $Result = [UIntPtr]::Zero
    [void][DotfilesFontResource]::SendMessageTimeout([IntPtr]0xffff, 0x001d, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$Result)
} finally {
    foreach ($File in $Files) { [IO.File]::Delete((Join-Path $Scratch $File)) }
    [IO.Directory]::Delete($Scratch)
}
