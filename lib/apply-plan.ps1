# Python selects operations; native transactions retain filesystem safeguards.
function Get-ApplyPlan {
    param([string]$RepoRoot, [string]$Items, [string]$TargetRoot, [string]$Session, [string[]]$Components = @(), [hashtable]$Roots = @{})
    if (-not $Roots.Count) { $Roots = @{ home=$env:USERPROFILE; app_data=$env:APPDATA; local_app_data=$TargetRoot } }
    $Rows = @(Invoke-DotfilesRequest apply-plan-native @{
        style='windows'; native_shell=(Get-Process -Id $PID).Path; repo=[IO.Path]::GetFullPath($RepoRoot);
        items=$Items; config=$TargetRoot; roots=$Roots; session=$Session; selection=$(if ($Components.Count) { @($Components) } else { $null })
    })
    ConvertFrom-ApplyRecords $Rows
}

function ConvertFrom-ApplyRecords {
    param([object[]]$Rows)
    foreach ($Row in $Rows) {
        if ($Row.privilege -cne 'none') { throw 'Unsupported Windows apply privilege' }
        @{ Component=$Row.component; Action=$Row.action; Source=$Row.source; Target=$Row.target;
           Backup=$Row.backup; Before=$Row.before; SourceState=$Row.source_state; Root=$Row.root;
           Reason=$Row.reason; schema_version=$Row.schema_version }
    }
}

function ConvertTo-ApplyRecords {
    param([object[]]$Plan)
    foreach ($Operation in $Plan) {
        @{ component=$Operation.Component; action=$Operation.Action; source=$Operation.Source; target=$Operation.Target;
           backup=$Operation.Backup; before=$Operation.Before; source_state=$Operation.SourceState; root=$Operation.Root;
           privilege='none'; reason=$Operation.Reason; schema_version=$Operation.schema_version }
    }
}
function Assert-ApplyPlan {
    param([object[]]$Plan)
    $null = Invoke-DotfilesRequest apply-validate @{style='windows';records=@(ConvertTo-ApplyRecords $Plan)}
}
function ConvertTo-ApplyPlanText {
    param([object[]]$Plan)
    Assert-ApplyPlan $Plan
    ConvertTo-DataContract 'apply-plan' @(ConvertTo-ApplyRecords $Plan)
}
function ConvertFrom-ApplyPlanText {
    param([string]$Text)
    $Rows = @(Read-DataContract 'apply-plan' $Text)
    $Plan = @(ConvertFrom-ApplyRecords $Rows)
    Assert-ApplyPlan $Plan
    $Plan
}
