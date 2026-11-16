# Shared profile validation and canonical formatting are owned by Python.
. (Join-Path $PSScriptRoot 'python.ps1')
function Read-WorkflowProfile {
    param([string]$Path)
    Invoke-DotfilesRule profile-read @{path=$Path} -AsHashtable
}
function ConvertTo-WorkflowProfileText {
    param([hashtable]$Profile)
    $Text = (@($Profile.Keys | ForEach-Object { "$_=$($Profile[$_])" }) -join "`n")
    Invoke-DotfilesRule profile-format @{text=$Text}
}

function Select-WorkflowInstallPlan {
    param([hashtable]$Profile, [object[]]$Plan, [hashtable]$Context = @{},
        [ValidateSet('offline','normal','resume')][string]$Mode = 'offline')
    $Values = @(Invoke-DotfilesRequest install-select-native @{
        style='windows'; native_shell=(Get-Process -Id $PID).Path; items=@($Plan); native_context=$Context;
        roots=$Profile.install; mode=$Mode; policy_path=[string]$script:DotfilesExecutionPolicyPath
    })
    foreach ($Value in $Values) { ConvertTo-DotfilesRecord $Value }
}

function Get-WorkflowComponents {
    param([hashtable]$Profile, [object[]]$Plan, [object[]]$ApplyItems)
    Invoke-DotfilesRequest install-components @{associations=$Profile.components;items=@($Plan);available=@($ApplyItems | ForEach-Object { $_.id })}
}

function Get-WorkflowProfilePath {
    param([string]$RepoRoot, [string]$Name)
    if ($Name -cnotmatch '^[a-z][a-z0-9-]*$') { throw 'Invalid profile name' }
    Join-Path $RepoRoot "workflow/profiles/$Name.conf"
}
