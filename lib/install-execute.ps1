function Invoke-InstallPlan {
    param([object[]]$Plan, [hashtable]$Context, [string]$ResultsPath)
    $NativeShell = (Get-Process -Id $PID).Path
    $null = Invoke-DotfilesRequest install-execute-native @{
        style='windows'; native_shell=$NativeShell; items=@($Plan); native_context=$Context;
        results=$ResultsPath; resume=[int][bool]$Context.ResumeItems; dry=[int][bool]$Context.DryRun
        policy_path=[string]$script:DotfilesExecutionPolicyPath
    } -Stream
}
