function Read-InstallSchema {
    $Fields = [ordered]@{}
    foreach ($Line in Get-Content -LiteralPath (Join-Path $InstallSchemaDirectory 'fields.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Parts = $Line.Split("`t")
        $Fields[$Parts[0]] = $Parts[1]
    }
    $Methods = @{}
    foreach ($Line in Get-Content -LiteralPath (Join-Path $InstallSchemaDirectory 'methods.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Parts = $Line.Split("`t")
        if ($Parts[4] -eq '-') { $Parts[4] = '' }
        $Methods[$Parts[0]] = @{ Platforms = $Parts[1].Split(' '); Required = $Parts[2].Split(' '); Kinds = $Parts[3].Split(' '); Optional = $Parts[4].Split(' ') }
    }
    $Sources = @{}
    foreach ($Line in Get-Content -LiteralPath (Join-Path $InstallSchemaDirectory 'sources.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Parts = $Line.Split("`t")
        $Sources[$Parts[0]] = if ($Parts[1] -eq '-') { '' } else { $Parts[1] }
    }
    $Providers = @{}
    foreach ($Line in Get-Content -LiteralPath (Join-Path $InstallSchemaDirectory 'runtime-providers.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Parts = $Line.Split("`t"); $Providers[$Parts[0]] = $Parts[1]
    }
    $Capabilities = @{}
    foreach ($Line in Get-Content -LiteralPath (Join-Path $InstallSchemaDirectory 'capabilities.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        if ($Line -cnotmatch '^[a-z][a-z0-9-]*$') { throw 'Invalid runtime capability' }
        $Capabilities[$Line] = $true
    }
    $DiscoveryRoots = @{}
    foreach ($Line in Get-Content -LiteralPath (Join-Path $InstallSchemaDirectory 'discovery-roots.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Parts = $Line.Split("`t")
        $DiscoveryRoots[$Parts[0]] = @{ Platforms=$Parts[1].Split(' '); Kinds=$Parts[2].Split(' ') }
    }
    @{ DiscoveryRoots = $DiscoveryRoots; Capabilities = $Capabilities; Fields = $Fields; Methods = $Methods; Sources = $Sources; Providers = $Providers }
}

function Test-InstallEntry {
    param([hashtable]$Entry, [string]$Platform, [hashtable]$Schema)
    $Method = $Schema.Methods[$Entry.method]
    if (-not $Method -or $Platform -cnotin $Method.Platforms) { throw "Unsupported method '$($Entry.method)' on $Platform" }
    if (-not $Entry.order -or $Entry.order.Length -gt 6) { throw 'order must be 0..999999' }
    if (-not $Entry.source_kind -or $Entry.source_kind -cnotin $Method.Kinds) { throw 'Unsupported source_kind' }
    $ValueField = $Schema.Sources[$Entry.source_kind]
    foreach ($Key in (@('order', 'method', 'source_kind') + $Method.Required + @($ValueField))) {
        if ($Key -and -not $Entry[$Key]) { throw "Missing $Key" }
    }
    $Allowed = @('order', 'method', 'source_kind', 'scope', 'check', 'depends_on', 'install_depends_on', 'environments', 'provides', 'wsl_provider', 'methods', 'preferred_method', 'detect_files', 'detect_dirs') + $Method.Required + $Method.Optional + @($ValueField)
    if ($ValueField -eq 'source_url') { $Allowed += 'mirror_url' }
    foreach ($Key in $Entry.Keys) {
        if ($Key -cnotin $Allowed) { throw "Unsupported field $Key for $($Entry.method)/$($Entry.source_kind)" }
        if ($Entry[$Key] -and $Entry[$Key] -cnotmatch ('^(' + $Schema.Fields[$Key] + ')$')) { throw "Invalid $Key" }
    }
    if ($Entry.method -cin @('winget', 'msvc', 'rustup', 'pipx') -and $Entry.packages -match ' ') { throw 'Method requires one package/toolchain' }
    if ($Entry.source_kind -cne 'cargo-index' -and ($Entry.source_url -cmatch '^sparse' -or $Entry.mirror_url -cmatch '^sparse')) { throw 'sparse+ URLs require cargo-index' }
    if ($Entry.method -ceq 'font-download') {
        if ($Entry.source_url -cnotmatch '^https://' -or $Entry.mirror_url) { throw 'font-download requires HTTPS and does not support mirrors' }
        $FontFiles = $Entry.font_files.Split(' ')
        if (@($FontFiles | Select-Object -Unique).Count -ne $FontFiles.Count) { throw 'Duplicate font filename' }
    }
    if ($Entry.provides -and -not $Schema.Capabilities.ContainsKey($Entry.provides)) { throw 'Unknown runtime capability' }
    if ($Entry.scope -and $Entry.environments) { throw 'scope and environments cannot be combined' }
    if ($Entry.wsl_provider) {
        if ($Platform -cnotmatch '^linux\.' -or $Entry.environments -cne 'native') { throw 'WSL provider requires native-only Linux installation' }
        if (-not $Schema.Providers.ContainsKey($Entry.wsl_provider) -or $Entry.provides -cne $Schema.Providers[$Entry.wsl_provider]) { throw 'Unknown or mismatched runtime provider' }
    }
    $Entry.order = [int]$Entry.order
}

function Get-InstallEnvironments {
    param([hashtable]$Item)
    $Environments = $Item.environments.Split(' ')
    $Environments
    if ($Item.wsl_provider) { 'wsl' }
}

function Read-InstallItems {
    param([string]$Directory, [string]$Platform)
    $Schema = Read-InstallSchema
    $All = @{}
    $Files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.conf' -File)
    if (-not $Files.Count) { throw 'No item configurations found' }
    foreach ($File in $Files) {
        if ($File.BaseName -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $File.Length -eq 0) { throw "Invalid or empty item: $File" }
        $Sections = @{}
        $Section = $null
        foreach ($RawLine in Get-Content -LiteralPath $File.FullName) {
            $Line = $RawLine.Trim([char[]]" `t`r")
            if (-not $Line -or $Line.StartsWith('#')) { continue }
            if ($Line -cmatch '^\[((?:macos|windows|linux\.(?:apt|dnf|pacman))(?:/[a-z][a-z-]*)?)\]$') {
                $Section = $Matches[1]
                if ($Sections.ContainsKey($Section)) { throw "Duplicate section in $File" }
                $Sections[$Section] = @{}
                continue
            }
            if (-not $Section -or $Line -notmatch '^([^=]+)=(.*)$') { throw "Invalid configuration line in ${File}: $Line" }
            $Key = $Matches[1]; $Value = $Matches[2]
            if ($Key -cnotin @($Schema.Fields.Keys) -or $Sections[$Section].ContainsKey($Key) -or $Value -match '[|\t]') { throw "Unknown/duplicate field or invalid value in ${File}: $Line" }
            $Sections[$Section][$Key] = $Value
        }
        foreach ($SectionName in $Sections.Keys) {
            if ($SectionName.Contains('/')) {
                $Parts = $SectionName.Split('/')
                if (-not $Sections.ContainsKey($Parts[0]) -or $Parts[1] -cnotin ([string]$Sections[$Parts[0]].methods).Split(' ')) { throw "Undeclared installation method section: $SectionName" }
                continue
            }
            $Entry = ConvertTo-InstallCanonicalItem (Resolve-InstallSections $Sections $SectionName $Schema)
            $Entry.id = $File.BaseName
            $All["$SectionName/$($File.BaseName)"] = $Entry
        }
    }
    $Platforms = @('linux.apt', 'linux.dnf', 'linux.pacman', 'macos', 'windows')
    if ($Platform -cnotin $Platforms) { throw 'Unknown target platform' }
    $Output = @()
    # Validate every graph before returning any selected-platform items.
    foreach ($Target in $Platforms) {
        $Items = @{}
        foreach ($Key in $All.Keys) {
            if ($Key.StartsWith("$Target/", [StringComparison]::Ordinal)) { $Items[$All[$Key].id] = $All[$Key] }
        }
        foreach ($Entry in $Items.Values) {
            $Seen = @{}
            foreach ($Dependency in @($Entry.depends_on -split ' ' | Where-Object { $_ })) {
                if (-not $Items.ContainsKey($Dependency)) { throw "Missing dependency $Dependency for $($Entry.id) on $Target" }
                if ($Seen.ContainsKey($Dependency)) { throw "Duplicate dependency $Dependency" }
                $Seen[$Dependency] = $true
                foreach ($Environment in @(Get-InstallEnvironments $Entry)) {
                    if ($Environment -cnotin @(Get-InstallEnvironments $Items[$Dependency])) { throw "Dependency unavailable in $Environment environment" }
                }
            }
        }
        $Done = @{}
        while ($Done.Count -lt $Items.Count) {
            $Best = $null
            foreach ($Entry in $Items.Values) {
                if ($Done.ContainsKey($Entry.id)) { continue }
                $Ready = $true
                foreach ($Dependency in @($Entry.depends_on -split ' ' | Where-Object { $_ })) {
                    if (-not $Done.ContainsKey($Dependency)) { $Ready = $false }
                }
                if ($Ready -and (-not $Best -or $Entry.order -lt $Best.order -or
                    ($Entry.order -eq $Best.order -and [StringComparer]::Ordinal.Compare($Entry.id, $Best.id) -lt 0))) { $Best = $Entry }
            }
            if (-not $Best) { throw "Dependency cycle on $Target" }
            $Done[$Best.id] = $true
            if ($Target -ceq $Platform) { $Output += $Best }
        }
    }
    $Output
}

