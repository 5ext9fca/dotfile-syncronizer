# Legacy declaration adapter. Core planning consumes only normalized fields.
function ConvertTo-InstallCanonicalItem {
    param([hashtable]$Entry)
    $Item = $Entry.Clone()
    if (-not $Item.environments) { $Item.environments = if ($Item.scope -eq 'desktop') { 'native' } else { 'native wsl' } }
    $Item.probe_command = [string]$Item.check
    $Item.Remove('scope'); $Item.Remove('check')
    if (-not $Item.methods) { $Item.methods = $Item.method }
    if (-not $Item.preferred_method) { $Item.preferred_method = $Item.method }
    $Item
}
