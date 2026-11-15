function Get-InstallPlan {
    param([string]$Directory, [string]$Platform = 'windows', [bool]$Mirrors = $true,
        [bool]$Wsl = $false, [bool]$Inspect = $true, [hashtable]$Context = @{})
    $null = Get-InstallExecutionPolicy '*' install
    $Items = @(Read-InstallItems -Directory $Directory -Platform $Platform)
    foreach ($Item in $Items) {
        $Item.schema_version = Get-DataContractVersion install-plan
        $Item.action = 'install'; $Item.reason = 'requested'; $Item.source_origin = 'config'; $Item.state = ''; $Item.detected_method = ''; $Item.detected_paths = ''; $Item.decision_reason = 'offline-preferred-method'
        if ($Mirrors -and $Item.mirror_url) { $Item.source_url = $Item.mirror_url; $Item.source_origin = 'mirror' }
        $Environment = if ($Wsl) { 'wsl' } else { 'native' }
        if ($Wsl -and $Item.wsl_provider) { $Item.action = 'skip'; $Item.reason = "provided-by-host:$($Item.wsl_provider)"; $Item.state = "provider:$($Item.wsl_provider)" }
        elseif ($Item.environments -and $Environment -cnotin $Item.environments.Split(' ')) { $Item.action = 'skip'; $Item.reason = "environment-not-selected:$Environment" }
        elseif ($Inspect) {
            if ($Platform -ne 'windows') { throw 'PowerShell can inspect only the Windows host; use offline planning for other platforms' }
            $Item = Get-InstallObservedItem $Item $Context normal
        }
        if ($Item.reason -match '^(provided-by-host:|environment-not-selected:)') { $Item.decision_reason = $Item.reason }
        $Item
    }
}

function Assert-InstallPlan {
    param([object[]]$Plan)
    foreach ($Item in $Plan) {
        if ([string]$Item.schema_version -cne [string](Get-DataContractVersion install-plan)) { throw 'Unsupported install plan record version' }
        if ($Item.action -cnotin @('install', 'upgrade', 'skip')) { throw 'Invalid install action' }
    }
}
function ConvertTo-InstallPlanText {
    param([object[]]$Plan, [switch]$Envelope)
    Assert-InstallPlan $Plan
    $Text = ConvertTo-DataContract 'install-plan' $Plan
    if ($Envelope) { $Text.Split("`n") }
    else { $Text.Split("`n") | Select-Object -Skip 2 }
}
function ConvertFrom-InstallPlanText {
    param([string]$Text)
    $Plan = @(Read-DataContract 'install-plan' $Text)
    Assert-InstallPlan $Plan
    $Plan
}

