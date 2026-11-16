$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $RepoRoot 'lib/apply-items.ps1')
$Work = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
function Assert-ApplyTest { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message } }
function New-ApplyTestCase {
    param([string]$Name)
    $script:CaseRoot = Join-Path $Work $Name
    foreach ($Dir in @('repo/tool/nested', 'config', 'items')) { New-Item -ItemType Directory -Path (Join-Path $CaseRoot $Dir) -Force | Out-Null }
    "[windows]`nsource=tool`ntarget_root=local_app_data`ntarget=tool`nmethod=copy`nexclude=runtime" | Set-Content -LiteralPath (Join-Path $CaseRoot 'items/tool.conf')
    'new' | Set-Content -LiteralPath (Join-Path $CaseRoot 'repo/tool/nested/a file')
    'state' | Set-Content -LiteralPath (Join-Path $CaseRoot 'repo/tool/runtime')
    $script:Session = Join-Path $CaseRoot 'backups/session'
}
function Get-TestPlan {
    param([string[]]$Components = @())
    Get-ApplyPlan -RepoRoot (Join-Path $CaseRoot 'repo') -Items (Join-Path $CaseRoot 'items') -TargetRoot (Join-Path $CaseRoot 'config') -Session $Session -Components $Components
}
try {
    New-ApplyTestCase 'dry'
    $Plan = @(Get-TestPlan)
    Invoke-ApplyPlan $Plan $Session $true
    Assert-ApplyTest (-not (Test-Path (Join-Path $CaseRoot 'config/tool')) -and -not (Test-Path $Session)) 'Dry-run wrote files'
    $Failed = $false
    try { $null = @(Get-TestPlan @('tool', 'unknown')) } catch { $Failed = $true }
    Assert-ApplyTest $Failed 'Unknown component accepted'
    New-ApplyTestCase 'results'
    $Plan = @(Get-TestPlan); $Failed = $false
    try { Invoke-ApplyPlan $Plan $Session $false (Join-Path $CaseRoot 'repo/tool/nested/a file') } catch { $Failed = $true }
    Assert-ApplyTest ($Failed -and -not (Test-Path $Session)) 'Report path can overwrite deployment source'
    New-ApplyTestCase 'basic'
    $Plan = @(Get-TestPlan); Invoke-ApplyPlan $Plan $Session $false
    Assert-ApplyTest ((Get-Content (Join-Path $CaseRoot 'config/tool/nested/a file')) -eq 'new') 'Copy failed'
    Assert-ApplyTest (-not (Test-Path (Join-Path $CaseRoot 'config/tool/runtime'))) 'Runtime state copied'
    $Again = @(Get-TestPlan); Assert-ApplyTest (@($Again | Where-Object Action -ne 'skip').Count -eq 0) 'Apply is not idempotent'
    'user data' | Set-Content (Join-Path $CaseRoot 'config/tool/untracked')
    $Failed = $false
    try { Restore-ApplyJournal (Join-Path $Session 'journal.jsonl') $false } catch { $Failed = $true }
    Assert-ApplyTest $Failed 'Restored over application data'
    Assert-ApplyTest (Test-Path (Join-Path $CaseRoot 'config/tool/nested/a file')) 'Restoration started before complete validation'
    Remove-Item (Join-Path $CaseRoot 'config/tool/untracked')
    Restore-ApplyJournal (Join-Path $Session 'journal.jsonl') $true
    Assert-ApplyTest (Test-Path (Join-Path $CaseRoot 'config/tool/nested/a file')) 'Restore dry-run changed files'
    Restore-ApplyJournal (Join-Path $Session 'journal.jsonl') $false
    Assert-ApplyTest (-not (Test-Path (Join-Path $CaseRoot 'config/tool'))) 'Created directory not removed'
    Restore-ApplyJournal (Join-Path $Session 'journal.jsonl') $false

    New-ApplyTestCase 'directory-conflict'
    New-Item -ItemType Directory -Path (Join-Path $CaseRoot 'config/tool/nested/a file') -Force | Out-Null
    'old' | Set-Content (Join-Path $CaseRoot 'config/tool/nested/a file/old')
    $Plan = @(Get-TestPlan); Invoke-ApplyPlan $Plan $Session $false
    Restore-ApplyJournal (Join-Path $Session 'journal.jsonl') $false
    Assert-ApplyTest ((Get-Content (Join-Path $CaseRoot 'config/tool/nested/a file/old')) -eq 'old') 'Directory backup lost'

    New-ApplyTestCase 'reparse'
    New-Item -ItemType Directory -Path (Join-Path $CaseRoot 'config/tool') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $CaseRoot 'external') | Out-Null
    'external' | Set-Content (Join-Path $CaseRoot 'external/a file')
    $LinkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $LinkType -Path (Join-Path $CaseRoot 'config/tool/nested') -Target (Join-Path $CaseRoot 'external') | Out-Null
    $Plan = @(Get-TestPlan); Invoke-ApplyPlan $Plan $Session $false
    Assert-ApplyTest ((Get-Content (Join-Path $CaseRoot 'external/a file')) -eq 'external') 'Followed a target reparse point'
    Restore-ApplyJournal (Join-Path $Session 'journal.jsonl') $false
    Assert-ApplyTest (Test-ApplyLink (Get-ApplyEntry (Join-Path $CaseRoot 'config/tool/nested'))) 'Reparse point was not restored'

    New-ApplyTestCase "rollback's"
    New-Item -ItemType Directory -Path (Join-Path $CaseRoot 'config/tool/nested') -Force | Out-Null
    'old' | Set-Content (Join-Path $CaseRoot 'config/tool/nested/a file')
    $Plan = @(Get-TestPlan)
    function Publish-ApplyObject {
        param([string]$Source, [string]$Target)
        if ([IO.Path]::GetFileName($Source) -eq 'new') { throw 'Injected publication failure' }
        if (Get-ApplyEntry $Target) { throw 'Unexpected destination' }
        Move-Item -LiteralPath $Source -Destination $Target -ErrorAction Stop
    }
    $Failed = $false
    # Publication fault injection belongs to the retained native transaction.
    New-Item -ItemType Directory -Path $Session -Force | Out-Null
    $Journal = Join-Path $Session 'journal.jsonl'
    '{"version":1}' | Set-Content -LiteralPath $Journal -Encoding UTF8
    $Operation = @($Plan | Where-Object Action -eq 'copy')[0]
    try { Invoke-ApplyTransaction $Operation $Journal 1 } catch { $Failed = $true }
    Assert-ApplyTest ($Failed -and (Get-Content (Join-Path $CaseRoot 'config/tool/nested/a file')) -eq 'old') 'Automatic rollback did not preserve original'
    . (Join-Path $RepoRoot 'apply/handlers/files.ps1')

    New-ApplyTestCase 'modified'
    $Plan = @(Get-TestPlan); Invoke-ApplyPlan $Plan $Session $false
    'user edit' | Set-Content (Join-Path $CaseRoot 'config/tool/nested/a file')
    $Failed = $false
    try { Restore-ApplyJournal (Join-Path $Session 'journal.jsonl') $false } catch { $Failed = $true }
    Assert-ApplyTest ($Failed -and (Get-Content (Join-Path $CaseRoot 'config/tool/nested/a file')) -eq 'user edit') 'User edit was overwritten'
    New-ApplyTestCase 'overlap'
    Copy-Item (Join-Path $CaseRoot 'items/tool.conf') (Join-Path $CaseRoot 'items/other.conf')
    $Failed = $false
    try { $null = @(Get-TestPlan) } catch { $Failed = $true }
    Assert-ApplyTest $Failed 'Overlapping components accepted'
    Write-Host 'PowerShell apply planning, transaction and recovery tests passed.'
} finally { if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force } }
