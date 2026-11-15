$ErrorActionPreference = 'Stop'
$Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $Repo 'lib/workflow.ps1')
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('profile-roots-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action) {
    $Failed = $false
    try { & $Action | Out-Null } catch { $Failed = $true }
    Assert $Failed 'Expected rejection'
}
try {
    foreach ($Name in @('linux', 'macos', 'windows', 'wsl')) {
        $Profile = Read-WorkflowProfile (Get-WorkflowProfilePath $Repo $Name)
        Assert ($Profile.install -ceq 'none' -and $Profile.components -notmatch 'desktop-fonts') 'Incorrect default'
        Assert (@(Select-WorkflowInstallPlan $Profile @()).Count -eq 0) 'none selected installation'
        $Full = Read-WorkflowProfile (Get-WorkflowProfilePath $Repo "$Name-full")
        Assert ($Full.install -ceq 'all') 'Full profile lost installation'
    }
    Reject { Get-WorkflowProfilePath $Repo '../windows' }
    Reject { Get-WorkflowProfilePath $Repo 'Windows' }
    Reject { Read-WorkflowProfile (Get-WorkflowProfilePath $Repo 'missing') }
    $Source = Join-Path $Temp 'source'; $Items = Join-Path $Temp 'items'; $HomeRoot = Join-Path $Temp 'home'
    $null = New-Item -ItemType Directory $Source, $Items, $HomeRoot
    'source' | Set-Content (Join-Path $Source 'file')
    "[windows]`nsource=file`ntarget_root=home`ntarget=.gitconfig`nmethod=copy" | Set-Content (Join-Path $Items 'git.conf')
    $Roots = @{ home = $HomeRoot; app_data = ''; local_app_data = 'invalid-relative' }
    $Session = Join-Path $Temp 'backup'
    $Plan = @(Get-ApplyPlan $Source $Items '' $Session @('git') $Roots)
    Assert ($Plan.Count -eq 1 -and $Plan[0].Target -eq (Join-Path $HomeRoot '.gitconfig')) 'Wrong home target'
    Assert (@(Get-ApplyPlan $Source $Items '' $Session @('none') @{}).Count -eq 0) 'none became all'
    Reject { Get-ApplyPlan $Source $Items '' $Session @('git') @{ home = '' } }
    Reject { Get-ApplyPlan $Source $Items '' $Session @('git') @{ home = 'relative' } }
    # APPDATA can be independently mapped; same final path across roots conflicts.
    "[windows]`nsource=file`ntarget_root=app_data`ntarget=.gitconfig`nmethod=copy" | Set-Content (Join-Path $Items 'other.conf')
    Reject { Get-ApplyPlan $Source $Items '' $Session @() @{ home = $HomeRoot; app_data = $HomeRoot } }
    $Plan = @(Get-ApplyPlan $Source $Items '' $Session @('other') @{ app_data = $HomeRoot })
    Assert ($Plan.Count -eq 1) 'APPDATA mapping failed'
    # Default workflow must not inspect installation or WSL, and needs no WinGet.
    function Get-InstallPlan { throw 'Unexpected installation discovery' }
    function Get-WindowsWorkflowWslPlan { throw 'Unexpected WSL' }
    $Options = @{
        RepoRoot = $Repo; SessionId = 'default'; DryRun = $true; PlanOnly = $true; NoChinaMirrors = $false
        ResultsPath = ''; OnlyStage = ''; FromStage = ''; ConfigRoot = Join-Path $Temp 'config'
        BackupRoot = Join-Path $Temp 'backups'; ProgramFiles = ''; VsInstallerRoot = ''; GitConfigPaths = @()
    }
    $Context = New-WindowsWorkflowContext $Options
    Initialize-WindowsWorkflow $Context
    Assert ((@($Context.StagePlan | Where-Object Enabled | ForEach-Object Id) -join ',') -ceq 'configuration') 'Default enabled extra stages'
    Assert $Context.NoChinaMirrors 'Default enabled mirrors'
    Assert (-not (Test-Path $Context.SessionPath)) 'Preflight created session'
    Write-Host 'Profile defaults and controlled Windows target roots passed.'
} finally { Remove-Item -LiteralPath $Temp -Recurse -Force }
