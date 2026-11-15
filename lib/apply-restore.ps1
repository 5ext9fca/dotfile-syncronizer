function Restore-ApplyJournalUnlocked {
    param([string]$Journal, [bool]$DryRun)
    $Lines = @(Get-Content -LiteralPath $Journal -ErrorAction Stop)
    if (-not $Lines.Count -or ($Lines[0] | ConvertFrom-Json).version -ne 1) { throw 'Unsupported apply journal' }
    $Session = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Journal)); $Latest = @{}
    foreach ($Line in $Lines | Select-Object -Skip 1) {
        $Record = $Line | ConvertFrom-Json
        if ($Record.State -notin @('prepared', 'applied', 'rolled-back', 'restored') -or $Record.Sequence -lt 1) { throw 'Invalid journal record' }
        $Latest[$Record.Sequence] = $Record
    }
    $Active = @($Latest.Values | Where-Object State -in @('prepared', 'applied') | Sort-Object Sequence -Descending)
    # Validate the entire recovery before changing anything.
    foreach ($Record in $Active) {
        if ($Record.Action -notin @('mkdir', 'copy')) { throw 'Invalid journal action' }
        if ($Record.Backup -and -not (Test-ApplyWithin $Record.Backup (Join-Path $Session 'files'))) { throw 'Backup outside journal session' }
        $Parent = [IO.Path]::GetDirectoryName($Record.Target)
        if ([IO.Path]::GetDirectoryName($Record.Stage) -ne $Parent -or -not ([IO.Path]::GetFileName($Record.Stage)).StartsWith('.dotfiles-apply.')) { throw 'Invalid staging path' }
        $StageEntry = Get-ApplyEntry $Record.Stage
        if ($StageEntry -and (-not $StageEntry.PSIsContainer -or (Test-ApplyLink $StageEntry))) { throw 'Staging directory was replaced' }
        if ($Record.Backup -and (Get-ApplyEntry $Record.Backup)) { Assert-ApplyParent $Session $Record.Backup }
        Assert-ApplyParent $Record.Root $Record.Target
        $Current = Get-ApplyState $Record.Target; $Entry = Get-ApplyEntry $Record.Target
        if ($Record.State -eq 'prepared' -and $Current -eq $Record.Before) { }
        elseif ($Record.Action -eq 'mkdir' -and $Entry -and $Entry.PSIsContainer -and -not (Test-ApplyLink $Entry) -and $Current.Split(':')[0] -eq $Record.After.Split(':')[0]) {
            foreach ($Child in @(Get-ApplyTree $Record.Target)) {
                $Allowed = $false
                foreach ($Other in $Active) { if ($Child.FullName -eq $Other.Target -or (Test-ApplyWithin $Child.FullName $Other.Stage)) { $Allowed = $true; break } }
                if (-not $Allowed) { throw "Directory has untracked content: $($Child.FullName)" }
            }
        } elseif ($Current -ne $Record.After -and -not ($Record.State -eq 'prepared' -and $Current -eq 'absent')) { throw "Refusing to restore modified target: $($Record.Target)" }
        if ($Record.Before -ne 'absent' -and $Current -ne $Record.Before) {
            $Expected = $Record.Before.Substring($Record.Before.IndexOf(':') + 1)
            if (($Record.Backup -and (Get-ApplyContent $Record.Backup) -eq $Expected) -or (Get-ApplyContent (Join-Path $Record.Stage 'old')) -eq $Expected) { }
            else { throw "Backup is missing or changed: $($Record.Backup)" }
        }
        $StagedNew = Join-Path $Record.Stage 'new'
        if ((Get-ApplyEntry $StagedNew) -and (Get-ApplyState $StagedNew) -ne $Record.After) { throw 'Staging content was modified' }
    }
    foreach ($Record in $Active) {
        if ($DryRun) { Write-Host "DRY RUN: restore $($Record.Target) from $($Record.Backup)"; continue }
        Undo-ApplyObject $Record
        $StagedNew = Join-Path $Record.Stage 'new'
        if (Get-ApplyEntry $StagedNew) {
            if ($Record.Action -eq 'mkdir') { [IO.Directory]::Delete($StagedNew, $false) }
            else { Remove-Item -LiteralPath $StagedNew -Force -ErrorAction Stop }
        }
        if (Get-ApplyEntry $Record.Stage) { [IO.Directory]::Delete($Record.Stage, $false) }
        $Restored = @{}; foreach ($Property in $Record.PSObject.Properties) { $Restored[$Property.Name] = $Property.Value }
        Add-ApplyJournal $Journal $Restored 'restored'
        Write-Host "$($Record.Target): restored"
    }
}
