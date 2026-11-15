# Windows platform adapter. Mutable state is carried in one explicit hashtable.
function New-WindowsWorkflowContext {
    param([hashtable]$Options)
    $Required = @('RepoRoot', 'SessionId', 'DryRun', 'PlanOnly', 'NoChinaMirrors', 'ResultsPath', 'OnlyStage', 'FromStage', 'ConfigRoot', 'BackupRoot', 'ProgramFiles', 'VsInstallerRoot', 'GitConfigPaths')
    foreach ($Key in $Required) { if (-not $Options.ContainsKey($Key)) { throw "Missing workflow context field $Key" } }
    foreach ($Key in $Options.Keys) { if ($Key -cnotin ($Required + @('Resume','MirrorsExplicit'))) { throw "Unknown workflow context field $Key" } }
    $Context = @{}
    foreach ($Key in $Required) { $Context[$Key] = $Options[$Key] }
    if ($Context.SessionId -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$') { throw 'Invalid session ID' }
    foreach ($Key in @('DryRun', 'PlanOnly', 'NoChinaMirrors')) { if ($Context[$Key] -isnot [bool]) { throw "Invalid boolean context field $Key" } }
    $Context.Resume = $Options.Resume; $Context.MirrorsExplicit = $Options.MirrorsExplicit
    $Context.ProfileName = 'windows'
    $Context.ConfigRoot = Resolve-ApplyRoot $Context.ConfigRoot
    $Context.SessionPath = Join-Path (Resolve-ApplyRoot $Context.BackupRoot) "workflow-$($Context.SessionId)"
    $Context.InstallContext = @{ DryRun = [bool]$Context.DryRun; ProgramFiles = $Context.ProgramFiles; VsInstallerRoot = $Context.VsInstallerRoot }
    $Context.GitSettings = @() # Personal identity is configured locally by the operator.
    $Context
}
function Get-WindowsWorkflowInstallPlan {
    param([hashtable]$Context)
    $Plan = @(Get-InstallPlan -Directory (Join-Path $Context.RepoRoot 'install/items') -Inspect $false -Context $Context.InstallContext)
    $Mode = if ($Context.Resume) { 'resume' } else { 'normal' }
    Select-WorkflowInstallPlan $Context.Profile $Plan $Context.InstallContext $Mode
}
function Get-WindowsWorkflowApplyPlan {
    param([hashtable]$Context)
    Get-ApplyPlan -RepoRoot $Context.RepoRoot -Items (Join-Path $Context.RepoRoot 'apply/items') -TargetRoot $Context.ConfigRoot -Session (Join-Path $Context.SessionPath 'configuration') -Components $Context.Components
}
function Get-WindowsWorkflowWslPlan {
    param([hashtable]$Context)
    Get-WorkflowWslPlan -RepoRoot $Context.RepoRoot -Distribution $Context.Profile.wsl -NoChinaMirrors $Context.NoChinaMirrors -SessionId $Context.SessionId -RecordReports (-not $Context.DryRun -or [bool]$Context.ResultsPath)
}
function Get-WindowsWorkflowGitPath {
    param([hashtable]$Context)
    $Command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($Command) { $Command.Source } else { Join-Path $Context.ProgramFiles 'Git/cmd/git.exe' }
}
function Initialize-WindowsWorkflow {
    param([hashtable]$Context)
    Initialize-WorkflowResume $Context
    $Context.Profile = Read-WorkflowProfile (Join-Path $Context.RepoRoot 'workflow/profiles/windows.conf')
    if ($Context.Profile.shell -cne 'none' -or $Context.Profile.mirrors -cne 'none') { throw 'Windows requires shell=none and mirrors=none; WSL owns Unix initialization.' }
    $Context.StagePlan = @(Get-WorkflowStagePlan windows $Context.Profile $Context.OnlyStage $Context.FromStage (-not $Context.NoChinaMirrors))
    Select-WorkflowResumeStages $Context
    $Context.InstallPlan = @(Get-WindowsWorkflowInstallPlan $Context)
    $Context.Components = @(Get-WorkflowComponents $Context.Profile $Context.InstallPlan @(Read-ApplyItems (Join-Path $Context.RepoRoot 'apply/items')))
    $Enabled = @($Context.StagePlan | Where-Object { $_.Enabled })
    $Protected = @($Context.RepoRoot, $Context.ConfigRoot)
    if ('git' -cin @($Enabled.Preflight)) { $Protected += $Context.GitConfigPaths }
    Assert-WorkflowOutput $Context.SessionPath $Protected
    if ($Context.ResultsPath) {
        $Context.ResultsPath = [IO.Path]::GetFullPath($Context.ResultsPath)
        Assert-WorkflowOutput $Context.ResultsPath ($Protected + @($Context.SessionPath))
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $Context.ResultsPath) -PathType Container)) { throw 'Results parent must exist' }
    }
    $Context.ApplyPlan = @(); $Context.WslPlan = $null
    foreach ($Stage in $Enabled) {
        switch -CaseSensitive ($Stage.Preflight) {
            'packages' { if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'WinGet is required; install Microsoft App Installer first.' } }
            'configuration' { $Context.ApplyPlan = @(Get-WindowsWorkflowApplyPlan $Context) }
            'wsl' { $Context.WslPlan = Get-WindowsWorkflowWslPlan $Context }
            'git' {
                $Git = Get-WindowsWorkflowGitPath $Context
                if (-not (Test-Path -LiteralPath $Git)) {
                    if ('packages' -cnotin @($Enabled.Action) -or -not @($Context.InstallPlan | Where-Object { $_.id -ceq 'git' }).Count) { throw 'Git stage requires an installed Git executable or the selected git item.' }
                } else {
                    foreach ($Setting in $Context.GitSettings) {
                        $Probe = Invoke-ManagedCommand probe $Git @('config', '--global', '--get', $Setting.Key) -TimeoutSeconds (Get-InstallExecutionPolicy '*' probe).TimeoutSeconds
                        if ($Probe.ExitCode -notin @(0, 1)) { throw (New-ExecutionException "Could not inspect Git $($Setting.Key) before installation." $Probe.ExitCode) }
                    }
                }
            }
            default { throw "Unsupported Windows prerequisite $($Stage.Preflight)" }
        }
    }
}
function Show-WindowsWorkflowPlan {
    param([hashtable]$Context)
    Write-Output "Workflow session: $($Context.SessionId) (profile=$($Context.ProfileName))"
    foreach ($Stage in $Context.StagePlan) {
        if (-not $Stage.Enabled) { Write-Output "Stage $($Stage.Id): skipped ($($Stage.Reason))"; continue }
        Write-Output "Stage $($Stage.Id):"
        switch -CaseSensitive ($Stage.Action) {
            'packages' { Show-InstallPlanExplanation $Context.InstallPlan windows $Context.Profile.install (Join-Path $Context.RepoRoot 'install/items'); ConvertTo-InstallPlanText -Plan $Context.InstallPlan -Envelope }
            'git' { foreach ($Setting in $Context.GitSettings) { Write-Output "Set global Git $($Setting.Key)=$($Setting.Value); recheck executable after packages." } }
            'configuration' { Show-ApplyPlanExplanation $Context.ApplyPlan; ConvertTo-ApplyPlanText $Context.ApplyPlan }
            'wsl' { $Context.WslPlan.Text }
            default { throw "Unsupported Windows action $($Stage.Action)" }
        }
    }
}
function Get-WindowsWorkflowActions {
    @{
        packages = {
            param($Context, $Report, $StageResultPath)
            $Context.InstallContext.ResumeItems = [bool]$Context.Resume
            $Plan = @(Get-WindowsWorkflowInstallPlan $Context)
            Invoke-InstallPlan -Plan $Plan -Context $Context.InstallContext -ResultsPath $Report
        }
        git = {
            param($Context, $Report, $StageResultPath)
            $Git = Get-WindowsWorkflowGitPath $Context
            if (-not $Context.DryRun -and -not (Test-Path -LiteralPath $Git)) { throw "Git not found after installation: $Git" }
            $Rows = @('key|status')
            foreach ($Setting in $Context.GitSettings) {
                $Current = $null
                if (Test-Path -LiteralPath $Git) {
                    $Probe = Invoke-ManagedCommand probe $Git @('config', '--global', '--get', $Setting.Key) -TimeoutSeconds (Get-InstallExecutionPolicy '*' probe).TimeoutSeconds
                    if ($Probe.ExitCode -notin @(0, 1)) { throw (New-ExecutionException "Could not inspect Git $($Setting.Key)" $Probe.ExitCode) }
                    $Current = $Probe.Stdout.TrimEnd("`r", "`n")
                }
                if ($Current -eq $Setting.Value) { $Status = 'skipped' }
                elseif ($Context.DryRun) { Write-Host "DRY RUN: Set global Git $($Setting.Key) to $($Setting.Value)"; $Status = 'planned' }
                else {
                    Invoke-InstallCommand $Context $Git @('config', '--global', '--replace-all', $Setting.Key, $Setting.Value)
                    $Status = 'success'
                }
                $Rows += "$($Setting.Key)|$Status"
            }
            Write-DataContractRows 'git-result' @($Rows | Select-Object -Skip 1) $Report
        }
        configuration = {
            param($Context, $Report, $StageResultPath)
            $Plan = @(Get-WindowsWorkflowApplyPlan $Context)
            Invoke-ApplyPlan -Plan $Plan -Session (Join-Path $Context.SessionPath 'configuration') -DryRun $Context.DryRun -ResultsPath $Report -StageResultPath $StageResultPath
        }
        wsl = {
            param($Context, $Report, $StageResultPath)
            $Fresh = Get-WindowsWorkflowWslPlan $Context
            $Arguments = $Fresh.Arguments
            if ($Context.DryRun) { $Arguments += '--dry-run' }
            if ($Fresh.HostReport) { Set-StageResultValue $StageResultPath child_report $Fresh.HostReport -Append }
            # Guest dry-run must execute to validate its configuration; the guest
            # receives --dry-run above and owns the non-mutating policy.
            $Result = Invoke-ManagedCommand mutation wsl.exe $Arguments -Stream
            if ($Result.ExitCode -ne 0) { throw (New-ExecutionException "WSL workflow failed with exit code $($Result.ExitCode)" $Result.ExitCode) }
        }
    }
}
function Invoke-WindowsWorkflow {
    param([hashtable]$Options)
    $Context = New-WindowsWorkflowContext $Options
    Initialize-WindowsWorkflow $Context
    if ($Context.PlanOnly) { Show-WindowsWorkflowPlan $Context; return }
    Invoke-WorkflowStages -Context $Context -Actions (Get-WindowsWorkflowActions)
}
