# Declarative deployment configuration and full filesystem preflight (PowerShell 5.1+).
function Test-ApplyRelativePath {
    param([string]$Path)
    if (-not $Path -or $Path -match '(^/|[:\\|\t\r\n])') { return $false }
    foreach ($Part in $Path.Split('/')) { if ($Part -in @('', '.', '..')) { return $false } }
    return $true
}

function Read-ApplyItems {
    param([string]$Directory, [string]$Platform = 'windows')
    $Schema = @{}
    foreach ($Line in Get-Content -LiteralPath (Join-Path $PSScriptRoot '../apply/schema/fields.tsv')) {
        if (-not $Line -or $Line.StartsWith('#')) { continue }
        $Key, $Pattern, $Required = $Line.Split("`t")
        $Schema[$Key] = @{ Pattern = $Pattern; Required = $Required }
    }
    $Files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.conf' -File)
    if (-not $Files.Count) { throw 'No apply item configurations found' }
    $Output = @{}
    foreach ($File in $Files) {
        if ($File.Length -eq 0 -or $File.BaseName -cnotmatch '^[a-z0-9][a-z0-9-]*$') { throw "Invalid component: $File" }
        $Sections = @{}; $Section = $null
        foreach ($Raw in Get-Content -LiteralPath $File.FullName) {
            $Line = $Raw.Trim([char[]]" `t`r")
            if (-not $Line -or $Line.StartsWith('#')) { continue }
            if ($Line -cmatch '^\[(unix|windows)\]$') {
                $Section = $Matches[1]
                if ($Sections.ContainsKey($Section)) { throw 'Duplicate platform section' }
                $Sections[$Section] = @{}
            } else {
                if (-not $Section -or $Line -notmatch '^([^=]+)=(.*)$') { throw 'Expected key=value in a section' }
                $Key = $Matches[1]; $Value = $Matches[2]
                if ($Key -cnotin @($Schema.Keys) -or $Sections[$Section].ContainsKey($Key) -or $Value -match '[|\t]') { throw 'Unknown/duplicate field or unsupported value' }
                $Sections[$Section][$Key] = $Value
            }
        }
        foreach ($Name in $Sections.Keys) {
            $Item = $Sections[$Name]
            foreach ($Key in $Schema.Keys) {
                if ($Schema[$Key].Required -eq 'yes' -and -not $Item[$Key]) { throw "Missing $Key" }
                if ($Item[$Key] -and $Item[$Key] -cnotmatch ('^(' + $Schema[$Key].Pattern + ')$')) { throw "Invalid $Key" }
            }
            if (-not (Test-ApplyRelativePath $Item.source) -or -not (Test-ApplyRelativePath $Item.target)) { throw 'Source and target must be safe relative paths' }
            if ($Item.exclude) { foreach ($Exclusion in $Item.exclude.Split(';')) { if (-not (Test-ApplyRelativePath $Exclusion)) { throw 'Invalid exclusion' } } }
            if ($Name -eq 'unix' -and $Item.target_root -cnotin @('home', 'config_home')) { throw 'Unix requires home or config_home' }
            if ($Name -eq 'windows' -and ($Item.target_root -cnotin @('home', 'app_data', 'local_app_data') -or $Item.method -cne 'copy')) { throw 'Windows requires home, app_data or local_app_data and copy' }
            if ($Item.renderer -and ($Name -cne 'unix' -or $Item.target_root -cne 'config_home' -or $Item.condition -cne 'linux-kde' -or $Item.method -cne 'hardlink')) { throw 'desktop-fonts requires Unix config_home linux-kde hardlink' }
            if ($Name -ceq 'windows' -and $Item.condition) { throw 'Conditions are Unix-only' }
            if ($Name -ceq $Platform) { $Item.id = $File.BaseName; $Output[$Item.id] = $Item }
        }
    }
    [string[]]$Ids = @($Output.Keys); [Array]::Sort($Ids, [StringComparer]::Ordinal)
    foreach ($Id in $Ids) { $Output[$Id] }
}

