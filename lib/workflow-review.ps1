. (Join-Path $PSScriptRoot 'install-report.ps1')
. (Join-Path $PSScriptRoot 'stage-result.ps1')
function Read-WorkflowRequest {
    param([string]$Session)
    if ((Get-Content -LiteralPath (Join-Path $Session 'request.tsv') -TotalCount 1) -cne '# dotfiles|workflow-request|2') { throw 'Incompatible session request; v2 required' }
    $Rows = @(Read-DataContract workflow-request ([IO.File]::ReadAllText((Join-Path $Session 'request.tsv'))))
    if ($Rows.Count -ne 1) { throw 'Expected one workflow request' }
    $Row = $Rows[0]
    if ($Row.platform -cnotmatch '^(linux\.(apt|dnf|pacman|none)|macos|windows)$' -or $Row.profile -cnotmatch '^[a-z][a-z0-9-]*$' -or $Row.china_mirrors -notmatch '^[01]$' -or $Row.dry_run -notmatch '^[01]$') { throw 'Invalid workflow request' }
    $Seen = @{}
    foreach ($Stage in $Row.selected_stages.Split(',')) {
        if ($Stage -cnotmatch '^[a-z][a-z0-9-]*$' -or $Seen.ContainsKey($Stage)) { throw 'Invalid selected stages' }
        $Seen[$Stage] = $true
    }
    $Row
}
function Read-WorkflowReview {
    param([string]$Session)
    [object[]]$Rows = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $Session 'workflow.json')))
    $Seen = @{}; $OutputRows = @()
    foreach ($Row in $Rows) {
        if ($Row.schema_version -ne 1 -or $Row.stage -cnotmatch '^[a-z][a-z0-9-]*$' -or $Seen.ContainsKey($Row.stage) -or $Row.status -cnotmatch '^(pending|running|success|planned|skipped|failed|blocked|deferred|interrupted)$' -or [string]$Row.exit_code -notmatch '^[0-9]+$') { throw 'Invalid workflow summary' }
        $Seen[$Row.stage] = $true
        $Metadata = Join-Path $Session "$($Row.stage).result"
        if (Test-Path -LiteralPath $Metadata) {
            $Values = @{}
            foreach ($Entry in @(Read-StageResult $Metadata)) { if ($Entry.key -notin @('recovery_journal', 'child_report')) { $Values[$Entry.key] = $Entry.value } }
            if ($Values.stage -cne $Row.stage) { throw 'Stage result identity mismatch' }
            if ($Row.status -cne $Values.status -or -not $Row.reason) { $Row.reason = $Values.reason }
            $Row.status = $Values.status; $Row.exit_code = [int]$Values.exit_code; $Row.report = $Values.report
        }
        $OutputRows += $Row
    }
    if (Test-Path -LiteralPath (Join-Path $Session 'request.tsv')) {
        $Request = Read-WorkflowRequest $Session
        foreach ($Stage in $Request.selected_stages.Split(',')) {
            if (-not $Seen.ContainsKey($Stage)) {
                $OutputRows += [pscustomobject]@{ stage=$Stage; status='pending'; exit_code=0; reason='not-started'; log=''; report='' }
            }
        }
    }
    $OutputRows
}
function Save-WorkflowRequest {
    param([hashtable]$Context, [string]$Directory)
    $Selected = @($Context.StagePlan | Where-Object Enabled | ForEach-Object Id) -join ','
    if (-not $Selected) { return }
    $Record = @{ platform = 'windows'; profile = $Context.ProfileName; china_mirrors = [int](-not $Context.NoChinaMirrors); selected_stages = $Selected; resume_parent = [string]$Context.Resume; dry_run = [int]$Context.DryRun }
    Write-AtomicReport (Join-Path $Directory 'request.tsv') (ConvertTo-DataContract workflow-request @($Record))
}
function Initialize-WorkflowResume {
    param([hashtable]$Context)
    if (-not $Context.Resume) { return }
    if ($Context.OnlyStage -or $Context.FromStage -or $Context.MirrorsExplicit -or $Context.ProfileExplicit) { throw '-Resume cannot be combined with profile, stage or mirror selectors' }
    $Context.Resume = (Resolve-Path -LiteralPath $Context.Resume).ProviderPath
    $Request = Read-WorkflowRequest $Context.Resume
    if ($Request.platform -cne 'windows' -or $Request.dry_run -ne '0') { throw 'Resume requires a real session on the same platform/profile' }
    $Rows = @(Read-WorkflowReview $Context.Resume)
    $Remaining = @(); $Failed = $false
    foreach ($Stage in $Request.selected_stages.Split(',')) {
        $Row = @($Rows | Where-Object stage -CEQ $Stage)
        if ($Row.Count -ne 1 -or $Row[0].status -cne 'success') { $Failed = $true }
        if ($Failed) { $Remaining += $Stage }
    }
    if (-not $Remaining.Count) { throw 'Session already completed; nothing to resume' }
    $Context.ProfileName = $Request.profile
    $Context.NoChinaMirrors = $Request.china_mirrors -eq '0'
    $Context.ResumeStages = $Remaining
}
function Select-WorkflowResumeStages {
    param([hashtable]$Context)
    if (-not $Context.Resume) { return }
    foreach ($Id in $Context.ResumeStages) { if ($Id -cnotin @($Context.StagePlan.Id)) { throw "Resume stage no longer exists: $Id" } }
    foreach ($Stage in $Context.StagePlan) {
        if ($Stage.Id -cnotin $Context.ResumeStages) { $Stage.Enabled = $false; $Stage.Reason = 'resume-selection' }
    }
}
function Show-WorkflowStatus {
    param([string]$Session)
    $Rows = @(Read-WorkflowReview $Session); $Retry = ''
    foreach ($Row in $Rows) {
        Write-Output "$($Row.stage): $($Row.status) (exit=$($Row.exit_code), $($Row.reason))"
        if (-not $Retry -and $Row.status -in @('failed','deferred','interrupted','running','blocked','pending')) { $Retry = $Row.stage }
        if ($Row.status -eq 'deferred') { Write-Output '  Action: complete the manual prerequisite, then retry.' }
        if ($Row.status -eq 'running') { Write-Output '  Action: incomplete record; verify the previous run has stopped before retrying.' }
        if ($Row.log) { Write-Output "  Log: $($Row.log)" }
        if ($Row.report) {
            Write-Output "  Detail report: $($Row.report)"
            if (Test-Path -LiteralPath $Row.report) {
                $Text = [IO.File]::ReadAllText($Row.report)
                $Kind = ($Text -split "`n")[0].TrimEnd("`r").Split('|')[1]
                if ($Kind -eq 'install-result') { Show-InstallResult @(Read-InstallResult $Text) }
                elseif ($Kind -in @('apply-result','git-result')) {
                    foreach ($Detail in @(Read-DataContract $Kind $Text)) {
                        if ($Detail.status -in @('failed','deferred','interrupted','running')) {
                            $Id = if ($Kind -eq 'install-result') { $Detail.id } elseif ($Kind -eq 'apply-result') { $Detail.component } else { $Detail.key }
                            Write-Output "  Item ${Id}: $($Detail.status) ($($Detail.reason))"
                        }
                    }
                }
            }
        }
        $Metadata = Join-Path $Session "$($Row.stage).result"
        if (Test-Path -LiteralPath $Metadata) {
            foreach ($Entry in @(Read-StageResult $Metadata)) {
                if ($Entry.key -eq 'recovery_journal') { Write-Output "  Recovery journal (inspect if configuration recovery is needed): $($Entry.value)" }
                if ($Entry.key -eq 'child_report') { Write-Output "  Child report: $($Entry.value)" }
            }
        } else {
            if ($Row.recovery_journal) { Write-Output "  Legacy recovery references: $($Row.recovery_journal)" }
            if ($Row.child_report) { Write-Output "  Legacy child reports: $($Row.child_report)" }
        }
    }
    if ($Retry) {
        if (Test-Path -LiteralPath (Join-Path $Session 'request.tsv')) {
            $Request = Read-WorkflowRequest $Session
            if ($Request.dry_run -eq '1') {
                Write-Output 'Recheck after resolving the cause: rerun the original command with -DryRun and the same stage selection and mirror options (dry-run sessions cannot be resumed).'
            } else {
                Write-Output ("Resume after resolving the cause: ./install/windows.ps1 -Resume '" + $Session.Replace("'", "''") + "'")
            }
        } else { Write-Output "Retry after resolving the cause: -FromStage $Retry (legacy session without saved selection)." }
    }
}
