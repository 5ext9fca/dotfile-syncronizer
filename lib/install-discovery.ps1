function Resolve-InstallDiscoveryPath {
    param([string]$Kind, [string]$Root, [string]$Relative, [hashtable]$Context)
    $PathType = if ($Kind -ceq 'file') { 'Leaf' } elseif ($Kind -ceq 'directory') { 'Container' } else { throw 'Invalid discovery kind' }
    if ($Root -ceq 'path') {
        if ($Kind -cne 'file' -or $Relative.Contains('/')) { throw 'path discovery requires a filename' }
        foreach ($Directory in ([string]$env:PATH).Split([IO.Path]::PathSeparator)) {
            if ($Directory -and (Test-Path -LiteralPath (Join-Path $Directory $Relative) -PathType Leaf -ErrorAction Stop)) { return [IO.Path]::GetFullPath((Join-Path $Directory $Relative)) }
        }
        return ''
    }
    $Base = switch -CaseSensitive ($Root) {
        home { $HOME }
        program_files { if ($Context.ProgramFiles) { $Context.ProgramFiles } else { $env:ProgramFiles } }
        program_files_x86 { ${env:ProgramFiles(x86)} }
        local_app_data { $env:LOCALAPPDATA }
        default { throw "Unsupported discovery root: $Root" }
    }
    if (-not $Base) { return '' }
    $Path = Join-Path $Base $Relative
    if (Test-Path -LiteralPath $Path -PathType $PathType -ErrorAction Stop) { return [IO.Path]::GetFullPath($Path) }
    ''
}
function Test-InstallDiscoveryPath {
    param([string]$Kind, [string]$Root, [string]$Relative, [hashtable]$Context)
    [bool](Resolve-InstallDiscoveryPath $Kind $Root $Relative $Context)
}
function Get-InstallDiscoveryObservation {
    param([hashtable]$Item, [hashtable]$Context)
    if (-not $Item.discovery) { return @{ State=''; Method=''; Paths='' } }
    $Groups = [ordered]@{}
    foreach ($Spec in $Item.discovery.Split(';')) {
        $Parts = ($Spec -split ':', 4)
        if ($Parts.Count -ne 4) { throw 'Malformed discovery plan' }
        $Method = $Parts[0]
        if (-not $Groups.Contains($Method)) { $Groups[$Method] = @{ Matches=$true; Paths=@() } }
        $Path = Resolve-InstallDiscoveryPath $Parts[1] $Parts[2] $Parts[3] $Context
        if ($Path) { $Groups[$Method].Paths += $Path } else { $Groups[$Method].Matches = $false }
    }
    foreach ($Method in $Groups.Keys) {
        if ($Groups[$Method].Matches) {
            $Paths = ConvertTo-Json -Compress -InputObject ([string[]]$Groups[$Method].Paths)
            return @{ State="discovered:$Method"; Method=$Method; Paths=$Paths.Replace('|', '\u007c') }
        }
    }
    @{ State=''; Method=''; Paths='' }
}

function Get-InstallDiscoveryState {
    param([hashtable]$Item, [hashtable]$Context)
    (Get-InstallDiscoveryObservation $Item $Context).State
}
