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
    $Value = Invoke-DotfilesRequest install-discover-native @{
        style='windows'; native_shell=(Get-Process -Id $PID).Path; specification=[string]$Item.discovery; native_context=$Context
    }
    ConvertTo-DotfilesRecord $Value
}

function Get-InstallDiscoveryState {
    param([hashtable]$Item, [hashtable]$Context)
    (Get-InstallDiscoveryObservation $Item $Context).State
}
