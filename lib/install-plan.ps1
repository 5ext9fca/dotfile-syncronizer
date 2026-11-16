function Get-InstallPlan {
    param([string]$Directory, [string]$Platform = 'windows', [bool]$Mirrors = $true,
        [bool]$Wsl = $false, [bool]$Inspect = $true, [hashtable]$Context = @{})
    $Items = @(Invoke-DotfilesRequest install-plan-native @{
        style='windows'; native_shell=(Get-Process -Id $PID).Path; directory=$Directory; platform=$Platform;
        mirrors=[int]$Mirrors; wsl=[int]$Wsl; inspect=[int]$Inspect; native_context=$Context;
        schema=$InstallSchemaDirectory; policy_path=[string]$script:DotfilesExecutionPolicyPath
    })
    foreach ($Value in $Items) {
        $Item = ConvertTo-DotfilesRecord $Value
        $Item.order = [int]$Item.order
        $Item
    }
}

function Assert-InstallPlan {
    param([object[]]$Plan)
    $Version = [string](Get-DataContractVersion install-plan)
    foreach ($Item in $Plan) {
        if ([string]$Item.schema_version -cne $Version) { throw 'Unsupported install plan record version' }
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

