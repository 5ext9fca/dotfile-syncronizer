function Publish-ApplyObject {
    param([string]$Source, [string]$Target)
    if (Get-ApplyEntry $Target) { throw "Target appeared during publication: $Target" }
    Move-Item -LiteralPath $Source -Destination $Target -ErrorAction Stop
}
function Add-ApplyJournal {
    param([string]$Journal, [hashtable]$Record, [string]$State)
    $Record.State = $State
    $Record | ConvertTo-Json -Depth 5 -Compress | Add-Content -LiteralPath $Journal -Encoding UTF8
}
function Undo-ApplyObject {
    param($Record)
    Assert-ApplyParent $Record.Root $Record.Target
    $Current = Get-ApplyState $Record.Target
    if ($Current -eq $Record.Before) { return }
    if ($Current -ne 'absent' -and $Current -ne $Record.After) { throw "Refusing to overwrite modified target: $($Record.Target)" }
    $Original = ''
    if ($Record.Before -ne 'absent') {
        $Expected = $Record.Before.Substring($Record.Before.IndexOf(':') + 1)
        $StagedOld = Join-Path $Record.Stage 'old'
        if ((Get-ApplyContent $StagedOld) -eq $Expected) { $Original = $StagedOld }
        elseif ($Record.Backup -and (Get-ApplyContent $Record.Backup) -eq $Expected) { $Original = $Record.Backup }
        else { throw "Backup is missing or modified: $($Record.Backup)" }
    }
    $Recovery = Join-Path ([IO.Path]::GetDirectoryName($Record.Target)) ('.dotfiles-restore.' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $Recovery -ErrorAction Stop | Out-Null
    $Installed = Join-Path $Recovery 'installed'
    if ($Current -ne 'absent') { Move-Item -LiteralPath $Record.Target -Destination $Installed -ErrorAction Stop }
    try { if ($Original) { Publish-ApplyObject $Original $Record.Target } }
    catch {
        if ($Current -ne 'absent') { Publish-ApplyObject $Installed $Record.Target }
        [IO.Directory]::Delete($Recovery, $false)
        throw
    }
    if ($Current -ne 'absent') {
        if ($Record.Action -eq 'mkdir') { [IO.Directory]::Delete($Installed, $false) }
        else { Remove-Item -LiteralPath $Installed -Force -ErrorAction Stop }
    }
    [IO.Directory]::Delete($Recovery, $false)
}
function Invoke-ApplyTransaction {
    param([hashtable]$Operation, [string]$Journal, [int]$Sequence)
    $Record = $Operation.Clone(); $Record.Sequence = $Sequence; $Prepared = $false; $Retain = $false
    Assert-ApplyParent $Record.Root $Record.Target
    if ((Get-ApplyState $Record.Target) -ne $Record.Before) { throw "Target changed since planning: $($Record.Target)" }
    if ($Record.Source -and (Get-ApplyState $Record.Source) -ne $Record.SourceState) { throw "Source changed since planning: $($Record.Source)" }
    $Record.Stage = Join-Path ([IO.Path]::GetDirectoryName($Record.Target)) ('.dotfiles-apply.' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $Record.Stage -ErrorAction Stop | Out-Null
    $New = Join-Path $Record.Stage 'new'
    try {
        if ($Record.Action -eq 'mkdir') { New-Item -ItemType Directory -Path $New -ErrorAction Stop | Out-Null }
        elseif ($Record.Action -eq 'copy') { Copy-Item -LiteralPath $Record.Source -Destination $New -ErrorAction Stop }
        else { throw "Unsupported action: $($Record.Action)" }
        $Record.After = Get-ApplyState $New
        Add-ApplyJournal $Journal $Record 'prepared'; $Prepared = $true
        Assert-ApplyParent $Record.Root $Record.Target
        if ((Get-ApplyState $Record.Target) -ne $Record.Before) { throw 'Target changed before backup' }
        if ($Record.Before -ne 'absent') {
            if (-not $Record.Backup -or (Get-ApplyEntry $Record.Backup)) { throw 'Invalid or occupied backup destination' }
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($Record.Backup)) -Force -ErrorAction Stop | Out-Null
            $Old = Join-Path $Record.Stage 'old'
            Move-Item -LiteralPath $Record.Target -Destination $Old -ErrorAction Stop
            Move-Item -LiteralPath $Old -Destination $Record.Backup -ErrorAction Stop
        }
        Assert-ApplyParent $Record.Root $Record.Target
        Publish-ApplyObject $New $Record.Target
        Add-ApplyJournal $Journal $Record 'applied'
    } catch {
        $Failure = $_
        if ($Prepared) {
            try { Undo-ApplyObject $Record; Add-ApplyJournal $Journal $Record 'rolled-back' }
            catch { $Retain = $true; Write-Warning "Automatic restoration incomplete; retained $($Record.Stage): $_" }
        }
        throw $Failure
    } finally {
        if (-not $Retain) {
            if (Get-ApplyEntry $New) {
                if ($Record.Action -eq 'mkdir') { [IO.Directory]::Delete($New, $false) }
                else { Remove-Item -LiteralPath $New -Force -ErrorAction Stop }
            }
            [IO.Directory]::Delete($Record.Stage, $false)
        }
    }
}
