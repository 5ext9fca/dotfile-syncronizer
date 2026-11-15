$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/command.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-command-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$Executable = (Get-Process -Id $PID).Path
try {
    Assert ((ConvertTo-NativeArgument '--list') -ceq '--list') 'WSL switches must remain unquoted'
    $Result = Invoke-ManagedCommand mutation missing-command -DryRun $true
    Assert ($Result.Status -eq 'planned') 'Dry run invoked a command'
    $Child = Join-Path $Temp 'arguments.ps1'
    [IO.File]::WriteAllText($Child, '[Console]::Out.Write((ConvertTo-Json -InputObject @($args) -Compress)); [Console]::Error.Write("warning"); exit 23')
    $Values = @('a b', '$(touch forbidden)', 'a"b', 'last\', '', '--list', 'space and trailing\')
    $Result = Invoke-ManagedCommand probe $Executable (@('-NoProfile', '-File', $Child) + $Values) -TimeoutSeconds 10
    Assert ($Result.ExitCode -eq 23 -and $Result.Status -eq 'failed') 'Exit code was lost'
    Assert ($Result.Stderr -ceq 'warning') 'Stderr was changed'
    $Actual = ConvertFrom-Json -InputObject $Result.Stdout
    Assert ($Actual.Count -eq $Values.Count) 'Argument count changed'
    for ($Index = 0; $Index -lt $Values.Count; $Index++) { Assert ($Actual[$Index] -ceq $Values[$Index]) "Argument changed: $Index" }
    # Exercise the legacy argv serializer even when this host has ArgumentList.
    $Legacy = [Diagnostics.ProcessStartInfo]::new()
    $Legacy.FileName = $Executable; $Legacy.UseShellExecute = $false
    $Legacy.RedirectStandardOutput = $true; $Legacy.RedirectStandardError = $true
    $Legacy.Arguments = (@((@('-NoProfile', '-File', $Child) + $Values) | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $Process = [Diagnostics.Process]::Start($Legacy)
    try {
        $LegacyOutput = $Process.StandardOutput.ReadToEnd()
        $LegacyError = $Process.StandardError.ReadToEnd()
        $Process.WaitForExit()
        Assert ($Process.ExitCode -eq 23 -and $LegacyError -ceq 'warning') 'Legacy process outcome changed'
        $Actual = ConvertFrom-Json -InputObject $LegacyOutput
        Assert ($Actual.Count -eq $Values.Count) 'Legacy argument count changed'
        for ($Index = 0; $Index -lt $Values.Count; $Index++) { Assert ($Actual[$Index] -ceq $Values[$Index]) "Legacy argument changed: $Index" }
    } finally { $Process.Dispose() }
    $Child = Join-Path $Temp 'slow.ps1'
    $Sentinel = Join-Path $Temp 'leaked'
    [IO.File]::WriteAllText($Child, 'Start-Sleep -Seconds 3; [IO.File]::WriteAllText($args[0], "leaked")')
    $Parent = Join-Path $Temp 'parent.ps1'
    [IO.File]::WriteAllText($Parent, '& $args[0] -NoProfile -File $args[1] $args[2]')
    $Result = Invoke-ManagedCommand probe $Executable @('-NoProfile', '-File', $Parent, $Executable, $Child, $Sentinel) -TimeoutSeconds 1
    Assert ($Result.ExitCode -eq 124 -and $Result.Status -eq 'timed-out') 'Timeout outcome incorrect'
    $Cancellation = [Threading.CancellationTokenSource]::new()
    try {
        $Cancellation.CancelAfter(300)
        $Result = Invoke-ManagedCommand mutation $Executable @('-NoProfile', '-File', $Parent, $Executable, $Child, $Sentinel) -CancellationToken $Cancellation.Token
        Assert ($Result.ExitCode -eq 130 -and $Result.Status -eq 'interrupted') 'Cancellation outcome incorrect'
    } finally { $Cancellation.Dispose() }
    Start-Sleep -Seconds 3
    Assert (-not (Test-Path $Sentinel)) 'Cancelled/timed-out process survived'
} finally { Remove-Item $Temp -Recurse -Force }
Write-Host 'Command arguments, capture, dry-run, exit codes, timeout and cancellation passed.'
