function Merge-InstallDependencies {
    param([string]$Common, [string]$Specific, [hashtable]$Schema)
    $Result = @()
    foreach ($Text in @($Common, $Specific)) {
        if ($Text -and $Text -cnotmatch ('^(' + $Schema.Fields.depends_on + ')$')) { throw 'Invalid depends_on' }
        $Seen = @{}
        foreach ($Id in @($Text.Split(' ') | Where-Object { $_ })) {
            if ($Seen.ContainsKey($Id)) { throw "Duplicate dependency $Id" }
            $Seen[$Id] = $true
            if ($Id -cnotin $Result) { $Result += $Id }
        }
    }
    $Result -join ' '
}
# Normalize typed, literal discovery paths without evaluating environment syntax.
function ConvertTo-InstallDiscoveryPaths {
    param([string]$Method, [string]$Kind, [string]$Text, [string]$Platform, [hashtable]$Roots)
    if (-not $Text) { return '' }
    $Result = @()
    foreach ($Path in $Text.Split(';')) {
        $Parts = ($Path -split ':', 2); $Root = $Parts[0]
        if ($Parts.Count -ne 2 -or $Root -cnotin @($Roots.Keys)) { throw 'Unknown discovery root' }
        if ($Platform -cnotin $Roots[$Root].Platforms -or $Kind -cnotin $Roots[$Root].Kinds) { throw 'Unsupported discovery root for platform/type' }
        $Relative = $Parts[1]
        if (-not $Relative -or $Relative -match '[\\|;:*?<>"\t]' -or @($Relative.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) { throw 'Invalid discovery path' }
        if ($Root -eq 'path' -and ($Kind -ne 'file' -or $Relative.Contains('/'))) { throw 'path discovery requires a filename' }
        $Result += "${Method}:${Kind}:$Path"
    }
    $Result -join ';'
}
function Resolve-InstallSections {
    param([hashtable]$Sections, [string]$Platform, [hashtable]$Schema)
    $Common = $Sections[$Platform]
    if (-not $Common.methods) {
        if ($Common.preferred_method) { throw 'preferred_method requires methods' }
        Test-InstallEntry $Common $Platform $Schema
        $Required = [string]$Common.depends_on
        $Common.depends_on = Merge-InstallDependencies $Required $Common.install_depends_on $Schema
        $Common.install_depends_on = (@(([string]$Common.install_depends_on).Split(' ') | Where-Object { $_ -and $_ -cnotin $Required.Split(' ') }) -join ' ')
        $Paths = @((ConvertTo-InstallDiscoveryPaths $Common.method file $Common.detect_files $Platform $Schema.DiscoveryRoots), (ConvertTo-InstallDiscoveryPaths $Common.method directory $Common.detect_dirs $Platform $Schema.DiscoveryRoots))
        $Common.discovery = ($Paths | Where-Object { $_ }) -join ';'
        if ($Common.discovery -and $Common.check) { throw 'check cannot be combined with discovery' }
        return $Common
    }
    $CommonFields = @('order','methods','preferred_method','depends_on','environments','provides','wsl_provider','scope')
    foreach ($Key in $Common.Keys) { if ($Key -cnotin $CommonFields) { throw "Method-specific field in common section: $Key" } }
    $Methods = $Common.methods.Split(' '); $Preferred = $Common.preferred_method
    if (-not $Preferred -or $Preferred -eq 'manual' -or $Preferred -cnotin $Methods) { throw 'Invalid preferred_method' }
    $Seen = @{}; $Discovery = @(); $Selected = $null
    foreach ($Method in $Methods) {
        if ($Seen.ContainsKey($Method)) { throw 'Duplicate installation method' }; $Seen[$Method] = $true
        $Name = "$Platform/$Method"
        if (-not $Sections.ContainsKey($Name)) { throw "Missing method section: $Name" }
        $Entry = $Common.Clone()
        foreach ($Key in $Sections[$Name].Keys) {
            if ($Key -ne 'depends_on' -and $Key -cin ($CommonFields + @('method','check','install_depends_on'))) { throw "Invalid method subsection field: $Key" }
            $Entry[$Key] = $Sections[$Name][$Key]
        }
        if ($Method -eq 'manual' -and $Sections[$Name].ContainsKey('depends_on')) { throw 'manual cannot declare installation dependencies' }
        $Entry.depends_on = Merge-InstallDependencies $Common.depends_on $Sections[$Name].depends_on $Schema
        $Entry.method = $Method
        if (-not $Entry.detect_files -and -not $Entry.detect_dirs) { throw 'Installation method requires discovery paths' }
        if ($Method -eq 'manual') {
            foreach ($Key in $Entry.Keys) { if ($Key -cnotin ($CommonFields + @('method','detect_files','detect_dirs'))) { throw 'manual is discovery-only' } }
        } else { Test-InstallEntry $Entry $Platform $Schema }
        $Discovery += ConvertTo-InstallDiscoveryPaths $Method file $Entry.detect_files $Platform $Schema.DiscoveryRoots
        $Discovery += ConvertTo-InstallDiscoveryPaths $Method directory $Entry.detect_dirs $Platform $Schema.DiscoveryRoots
        if ($Method -ceq $Preferred) { $Selected = $Entry }
    }
    $Selected.install_depends_on = (@(([string]$Sections["$Platform/$Preferred"].depends_on).Split(' ') | Where-Object { $_ -and $_ -cnotin ([string]$Common.depends_on).Split(' ') }) -join ' ')
    $Selected.discovery = ($Discovery | Where-Object { $_ }) -join ';'
    $Selected
}
