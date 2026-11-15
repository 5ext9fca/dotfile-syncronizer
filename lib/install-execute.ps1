function Invoke-InstallPlan {
    param([object[]]$Plan, [hashtable]$Context, [string]$ResultsPath)
    Assert-InstallPlan $Plan
    $null = Get-InstallExecutionPolicy '*' install
    $Results = @(); $Failure = $null
    foreach ($Item in $Plan) {
        $Timer = [Diagnostics.Stopwatch]::StartNew()
        $Reason = $Item.reason
        $ProbeFailure = $null; $Observed = $true
        if (-not $Failure -and $Context.ResumeItems) {
            if ($ResultsPath) { Write-DataContractRows install-result @($Results + (New-InstallResultRow $Item running 0 checking-current-state $false)) $ResultsPath }
            try { $Item = Get-WindowsResumeItem $Item $Context; $Reason = $Item.reason } catch { $ProbeFailure = $_; $Observed = $false }
        }
        if ($Failure) { $Status = 'blocked'; $Reason = 'previous-failure'; $Observed = $false }
        elseif (-not $ProbeFailure -and $Item.action -eq 'skip') { $Status = 'skipped' }
        else {
            try {
                if ($ProbeFailure) { throw $ProbeFailure }
                if ($ResultsPath) { Write-DataContractRows install-result @($Results + (New-InstallResultRow $Item running 0 $Reason)) $ResultsPath }
                Write-Host "Install $($Item.id): $($Item.action) ($($Item.method), source=$($Item.source_origin))"
                $ItemContext = $Context.Clone(); $ItemContext.Method = $Item.method
                switch -CaseSensitive ($Item.method) {
                    'winget' { Install-WinGetItem -Item $Item -Context $ItemContext }
                    'msvc' { Install-MsvcItem -Item $Item -Context $ItemContext }
                    default { throw "Unsupported Windows handler: $($Item.method)" }
                }
                $Status = if ($Context.DryRun) { 'planned' } else { 'success' }
            } catch { $Failure = $_; $Outcome = Get-ExecutionResult (Get-ExecutionExceptionCode $_.Exception) $Context.DryRun; $Status = $Outcome.Status; $Reason = $Outcome.Reason; Write-Warning $_.Exception.Message }
        }
        $Timer.Stop()
        $Result = New-InstallResultRow $Item $Status ([int]$Timer.Elapsed.TotalSeconds) $Reason $Observed
        $Results += $Result
        if ($ResultsPath) { Write-DataContractRows 'install-result' $Results $ResultsPath }
        Write-Host "Result $Result"
    }
    if ($ResultsPath) { Write-DataContractRows 'install-result' $Results $ResultsPath }
    Write-Host "Installation item summary:`n$($Results -join "`n")"
    if ($Failure) { throw $Failure }
}

