# Windows platform adapter. Mutable state is carried in one explicit hashtable.
function New-WindowsWorkflowContext {
    param([hashtable]$Options)
    $Required = @('RepoRoot', 'SessionId', 'DryRun', 'PlanOnly', 'NoChinaMirrors', 'ResultsPath', 'OnlyStage', 'FromStage', 'ConfigRoot', 'BackupRoot', 'ProgramFiles', 'VsInstallerRoot', 'GitConfigPaths')
    foreach ($Key in $Required) { if (-not $Options.ContainsKey($Key)) { throw "Missing workflow context field $Key" } }
    foreach ($Key in $Options.Keys) { if ($Key -cnotin ($Required + @('Resume','MirrorsExplicit','ProfileName','ProfileExplicit'))) { throw "Unknown workflow context field $Key" } }
    $Context = @{}
    foreach ($Key in $Required) { $Context[$Key] = $Options[$Key] }
    if ($Context.SessionId -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$') { throw 'Invalid session ID' }
    foreach ($Key in @('DryRun', 'PlanOnly', 'NoChinaMirrors')) { if ($Context[$Key] -isnot [bool]) { throw "Invalid boolean context field $Key" } }
    $Context.Resume = $Options.Resume; $Context.MirrorsExplicit = $Options.MirrorsExplicit
    $Context.ProfileExplicit = $Options.ProfileExplicit
    $Context.ProfileName = if ($Options.ProfileName) { $Options.ProfileName } else { 'windows' }
    $Context.SessionPath = Join-Path (Resolve-ApplyRoot $Context.BackupRoot) "workflow-$($Context.SessionId)"
    $Context.InstallContext = @{ DryRun = [bool]$Context.DryRun; ProgramFiles = $Context.ProgramFiles; VsInstallerRoot = $Context.VsInstallerRoot }
    $Context.Roots = @{ home=$env:USERPROFILE; app_data=$env:APPDATA; local_app_data=$Context.ConfigRoot }
    $Context.GitSettings = @() # Personal identity is configured locally by the operator.
    $Context
}
function Get-WindowsWorkflowWslPlan {
    param([hashtable]$Context)
    Get-WorkflowWslPlan -RepoRoot $Context.RepoRoot -Distribution $Context.Profile.wsl -GuestProfile $Context.Profile.wsl_profile -NoChinaMirrors $Context.NoChinaMirrors -SessionId $Context.SessionId -RecordReports (-not $Context.DryRun -or [bool]$Context.ResultsPath)
}
function Get-WindowsWorkflowGitPath {
    param([hashtable]$Context)
    $Command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($Command) { $Command.Source } else { Join-Path $Context.ProgramFiles 'Git/cmd/git.exe' }
}
function Initialize-WindowsWorkflow {
    param([hashtable]$Context)
    if ($Context.ResultsPath) { $Context.ResultsPath = [IO.Path]::GetFullPath($Context.ResultsPath) }
    $Prepared = Invoke-DotfilesRequest workflow-preflight-native @{
        style='windows';native_shell=(Get-Process -Id $PID).Path;native_context=$Context
    }
    foreach ($Property in $Prepared.PSObject.Properties) { $Context[$Property.Name] = $Property.Value }
    $Context.Profile = ConvertTo-DotfilesRecord $Context.Profile
    $Context.InstallContext = ConvertTo-DotfilesRecord $Context.InstallContext
    $Context.InstallPlan = @($Context.InstallPlan | ForEach-Object { ConvertTo-DotfilesRecord $_ })
    $Context.ApplyPlan = @(ConvertFrom-ApplyRecords $Context.ApplyPlan)
    if ($Context.WslPlan) { $Context.WslPlan = ConvertTo-DotfilesRecord $Context.WslPlan }
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
            $null = Invoke-DotfilesRequest workflow-packages-native @{
                style='windows';native_shell=(Get-Process -Id $PID).Path;native_context=$Context;report=$Report
            } -Stream
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
            $null = Invoke-DotfilesRequest apply-workflow-native @{
                style='windows'; native_shell=(Get-Process -Id $PID).Path; repo=$Context.RepoRoot;
                config=$Context.ConfigRoot; roots=$Context.Roots; session=(Join-Path $Context.SessionPath 'configuration');
                selection=@($Context.Components); dry=[bool]$Context.DryRun; results=$Report; metadata=$StageResultPath
            } -Stream
        }
        wsl = {
            param($Context, $Report, $StageResultPath)
            $Fresh = Get-WindowsWorkflowWslPlan $Context
            $Arguments = $Fresh.Arguments
            if ($Context.DryRun) { $Arguments += '--dry-run' }
            if ($Fresh.HostReport) { Set-StageResultValue $StageResultPath child_report $Fresh.HostReport -Append }
            # Guest dry-run must execute to validate its configuration; the guest
            # receives --dry-run above and owns the non-mutating policy.
            $Result = Invoke-WorkflowGuestCommand { Invoke-ManagedCommand mutation wsl.exe $Arguments -Stream }
            if ($Result.ExitCode -ne 0) { throw (New-ExecutionException "WSL workflow failed with exit code $($Result.ExitCode)" $Result.ExitCode) }
        }
    }
}
function Invoke-WindowsWorkflow {
    param([hashtable]$Options)
    $Context = New-WindowsWorkflowContext $Options
    Initialize-WindowsWorkflow $Context
    if ($Context.PlanOnly) { Show-WindowsWorkflowPlan $Context; return }
    Invoke-WorkflowStages -Context $Context
}
