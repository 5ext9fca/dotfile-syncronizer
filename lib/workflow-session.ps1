# The native wrapper holds the deployment lease for the complete core session.
function Invoke-WorkflowStagesUnlocked {
    param([hashtable]$Context)
    $null = Invoke-DotfilesRequest workflow-session-native @{
        style='windows';native_shell=(Get-Process -Id $PID).Path;native_context=$Context
    } -Stream
}

function Invoke-WorkflowStages {
    param([hashtable]$Context)
    Initialize-DotfilesPython
    Invoke-DeploymentLocked $Context.DryRun { Invoke-WorkflowStagesUnlocked $Context }
}
