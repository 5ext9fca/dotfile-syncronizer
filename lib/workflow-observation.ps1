# Read-only platform observations; Python selects and checks prerequisites.
function Invoke-NativeWorkflowQuery {
    param([string]$Query, [string[]]$Arguments, [hashtable]$Context)
    switch -CaseSensitive ($Query) {
        'command-present' { [string][int][bool](Get-Command $Arguments[0] -ErrorAction SilentlyContinue) }
        'git-path' {
            $Command = Get-Command git.exe -ErrorAction SilentlyContinue
            if ($Command) { $Command.Source } else { Join-Path $Arguments[0] 'Git/cmd/git.exe' }
        }
        'git-probe' {
            $Probe = Invoke-ManagedCommand probe $Arguments[0] @('config', '--global', '--get', $Arguments[1]) -TimeoutSeconds (Get-InstallExecutionPolicy '*' probe).TimeoutSeconds
            if ($Probe.ExitCode -notin @(0, 1)) { throw (New-ExecutionException "Could not inspect Git $($Arguments[1]) before installation." $Probe.ExitCode) }
        }
        'wsl-plan' {
            $Plan = Get-WorkflowWslPlan -RepoRoot $Context.RepoRoot -Distribution $Context.Profile.wsl -GuestProfile $Context.Profile.wsl_profile -NoChinaMirrors $Context.NoChinaMirrors -SessionId $Context.SessionId -RecordReports (-not $Context.DryRun -or [bool]$Context.ResultsPath)
            ConvertTo-Json -InputObject $Plan -Depth 8 -Compress
        }
        default { throw "Unsupported native workflow query: $Query" }
    }
}
