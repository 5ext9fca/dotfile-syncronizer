# Pure policy shared by ordinary planning and manually resumed runs.
function Get-InstallDecision {
    param([string]$State, [ValidateSet('normal', 'resume')][string]$Mode, [bool]$Discovery = $false)
    if ($State -eq 'upgrade') { $State = 'present' }
    $Decision = Get-InstallProbeResult $State
    $Reason = $Decision.Reason
    if ($Mode -eq 'resume') {
        if ($Decision.Action -eq 'skip') { $Reason = 'resume-already-installed' }
        elseif (-not $State) { $Reason = 'resume-recheck-required' }
    }
    $DecisionReason = if ($Discovery -and -not $State) { 'no-discovery-match' } else { $Reason }
    @{ DecisionReason = $DecisionReason; Action = $Decision.Action; Reason = $Reason; State = $State }
}
