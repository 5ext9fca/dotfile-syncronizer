# Compatibility surface only: shared declaration rules live in Python.
. (Join-Path $PSScriptRoot 'python.ps1')
function Read-InstallItems {
    param([string]$Directory, [string]$Platform)
    $Json = @(Invoke-DotfilesPython -Arguments @('install-read', '--directory', $Directory, '--platform', $Platform, '--schema', $InstallSchemaDirectory, '--json') 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ($Json -join "`n") }
    foreach ($Value in @((($Json -join "`n") | ConvertFrom-Json))) {
        $Item = @{}
        foreach ($Property in $Value.PSObject.Properties) { $Item[$Property.Name] = $Property.Value }
        $Item.order = [int]$Item.order
        $Item
    }
}
