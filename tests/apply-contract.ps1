$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $Repo 'lib/apply-items.ps1')
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-apply-contract-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Work
$Count = 0
try {
    foreach ($Line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/apply-operations/cases.tsv')) {
        if ($Line.StartsWith('#')) { continue }
        $Name, $Initial, $UnixAction, $WindowsAction, $UnixBackup, $WindowsBackup, $Guard = $Line.Split("`t")
        $CaseRoot = Join-Path $Work "$Name space"
        foreach ($Directory in @('repo', 'items', 'config')) { $null = New-Item -ItemType Directory (Join-Path $CaseRoot $Directory) }
        Copy-Item (Join-Path $PSScriptRoot 'fixtures/apply-operations/tool.conf') (Join-Path $CaseRoot 'items')
        $Source = Join-Path $CaseRoot 'repo/source.conf'; $Target = Join-Path $CaseRoot 'config/target.conf'; $Session = Join-Path $CaseRoot 'session'
        [IO.File]::WriteAllText($Source, "new`n")
        switch ($Initial) {
            'old' { [IO.File]::WriteAllText($Target, "original`n") }
            'same' { Copy-Item $Source $Target }
            'linked' { $null = New-Item -ItemType HardLink -Path $Target -Target $Source }
            'directory' { $null = New-Item -ItemType Directory $Target; [IO.File]::WriteAllText((Join-Path $Target 'nested'), "original`n") }
        }
        $Before = Get-ApplyState $Target
        $Arguments = @{ RepoRoot = Join-Path $CaseRoot 'repo'; Items = Join-Path $CaseRoot 'items'; TargetRoot = Join-Path $CaseRoot 'config'; Session = $Session }
        $Plan = @(Get-ApplyPlan @Arguments)
        $Operation = @($Plan | Where-Object { $_.Target -eq $Target })
        if ($Operation.Count -ne 1 -or $Operation[0].Action -cne $WindowsAction -or [int][bool]$Operation[0].Backup -ne [int]$WindowsBackup) { throw "Wrong filesystem plan for $Name" }
        Invoke-ApplyPlan -Plan $Plan -Session $Session -DryRun $false
        if ([IO.File]::ReadAllText($Target) -cne "new`n") { throw "Wrong contents for $Name" }
        $Arguments.Session = Join-Path $CaseRoot 'repeated'
        if (@(Get-ApplyPlan @Arguments | Where-Object { $_.Action -eq 'copy' }).Count) { throw "Not idempotent: $Name" }
        $Journal = Join-Path $Session 'journal.jsonl'
        if ($Guard -eq '1') {
            Remove-Item $Target; [IO.File]::WriteAllText($Target, "user change`n")
            $Rejected = $false
            try { Restore-ApplyJournal $Journal $false } catch { $Rejected = $true }
            if (-not $Rejected -or [IO.File]::ReadAllText($Target) -cne "user change`n") { throw 'Overwrote user modification' }
        } else {
            Restore-ApplyJournal $Journal $false
            if ((Get-ApplyState $Target) -cne $Before) { throw "Wrong restored state: $Name" }
        }
        $Count++
    }
    Write-Host "Apply filesystem contracts passed ($Count shared cases)."
} finally { Remove-Item -LiteralPath $Work -Recurse -Force }
