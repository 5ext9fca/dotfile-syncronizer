. (Join-Path $PSScriptRoot 'execution-result.ps1')

# Windows PowerShell 5.1 lacks ProcessStartInfo.ArgumentList. Encode argv using
# the Windows CRT rules; never pass arguments through a command shell.
function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # WSL parses leading switches before CRT-style quote removal.
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}
function Stop-CommandTree {
    param([Diagnostics.Process]$Process)
    if ($env:OS -eq 'Windows_NT') {
        # taskkill /T is available on supported Windows PowerShell 5.1 hosts.
        & "$env:SystemRoot/System32/taskkill.exe" /PID $Process.Id /T /F 2>&1 | Out-Null
    } else {
        try { $Process.Kill($true) } catch { if (-not $Process.HasExited) { throw } }
    }
    $Process.WaitForExit()
}
function Invoke-ManagedCommand {
    param(
        [ValidateSet('mutation', 'probe')][string]$Policy,
        [string]$Command,
        [object[]]$Arguments = @(),
        [bool]$DryRun = $false,
        [ValidateRange(0, 86400)][int]$TimeoutSeconds = 0,
        [switch]$Stream,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )
    if ($DryRun) {
        Write-Host "DRY RUN: $Command $($Arguments -join ' ')"
        return @{ Policy = $Policy; Status = 'planned'; ExitCode = 0; ElapsedSeconds = 0; Stdout = ''; Stderr = '' }
    }
    $Resolved = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $Resolved) { throw (New-ExecutionException "Required command is unavailable: $Command" 127) }
    $Info = [Diagnostics.ProcessStartInfo]::new()
    $Info.FileName = $Resolved.Source
    $Info.UseShellExecute = $false
    if ($null -ne $Info.PSObject.Properties['ArgumentList']) {
        foreach ($Argument in $Arguments) { $Info.ArgumentList.Add([string]$Argument) }
    } else {
        $Info.Arguments = (@($Arguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }) -join ' ')
    }
    $Info.RedirectStandardOutput = $true
    $Info.RedirectStandardError = $true
    $Info.RedirectStandardInput = -not $Stream
    $Process = [Diagnostics.Process]::new()
    $Process.StartInfo = $Info
    $Output = [Text.StringBuilder]::new()
    $Errors = [Text.StringBuilder]::new()
    $Watch = [Diagnostics.Stopwatch]::StartNew()
    $Started = $false; $Finished = $false; $Code = 0; $Status = 'success'
    try {
        $Started = $Process.Start()
        if ($Info.RedirectStandardInput) { $Process.StandardInput.Close() }
        $OutBuffer = [char[]]::new(4096)
        $ErrBuffer = [char[]]::new(4096)
        $OutTask = $Process.StandardOutput.ReadAsync($OutBuffer, 0, $OutBuffer.Length)
        $ErrTask = $Process.StandardError.ReadAsync($ErrBuffer, 0, $ErrBuffer.Length)
        while (-not $Process.HasExited -or $null -ne $OutTask -or $null -ne $ErrTask) {
            if ($CancellationToken.IsCancellationRequested) { $Code = 130; $Status = 'interrupted'; break }
            if ($TimeoutSeconds -gt 0 -and $Watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $Code = 124; $Status = 'timed-out'; break }
            if ($null -ne $OutTask -and $OutTask.IsCompleted) {
                $Count = $OutTask.GetAwaiter().GetResult()
                if ($Count -eq 0) { $OutTask = $null }
                else {
                    $Text = [string]::new($OutBuffer, 0, $Count)
                    $null = $Output.Append($Text)
                    if ($Stream) { Write-Host -NoNewline $Text }
                    $OutTask = $Process.StandardOutput.ReadAsync($OutBuffer, 0, $OutBuffer.Length)
                }
            }
            if ($null -ne $ErrTask -and $ErrTask.IsCompleted) {
                $Count = $ErrTask.GetAwaiter().GetResult()
                if ($Count -eq 0) { $ErrTask = $null }
                else {
                    $Text = [string]::new($ErrBuffer, 0, $Count)
                    $null = $Errors.Append($Text)
                    if ($Stream) { Write-Host -NoNewline $Text }
                    $ErrTask = $Process.StandardError.ReadAsync($ErrBuffer, 0, $ErrBuffer.Length)
                }
            }
            if (-not $Process.HasExited) { $null = $Process.WaitForExit(10) }
            elseif ($null -ne $OutTask -or $null -ne $ErrTask) { [Threading.Thread]::Sleep(10) }
        }
        if ($Status -in @('interrupted', 'timed-out')) { Stop-CommandTree $Process }
        else {
            $Process.WaitForExit()
            $Code = $Process.ExitCode
            if ($Code -in @(130, 143)) { $Status = 'interrupted' }
            elseif ($Code -ne 0) { $Status = 'failed' }
        }
        $Finished = $true
        return @{ Policy = $Policy; Status = $Status; ExitCode = $Code; ElapsedSeconds = [int]$Watch.Elapsed.TotalSeconds; Stdout = $Output.ToString(); Stderr = $Errors.ToString() }
    } finally {
        # Cancellation must finish process cleanup before the caller releases its lease.
        if ($Started -and -not $Finished) { Stop-CommandTree $Process }
        $Process.Dispose()
        $Watch.Stop()
    }
}
