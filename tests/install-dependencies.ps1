$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../lib/workflow.ps1')
. (Join-Path $PSScriptRoot 'fixtures/install/commands/setup.ps1')
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('dependencies-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $Temp
$PreviousPath = $env:PATH; $PreviousState = $env:DOTFILES_TEST_PACKAGE_STATE
try {
    $Fixture = Join-Path $PSScriptRoot 'fixtures/install/method-dependencies'
    Copy-Item (Join-Path $Fixture '*.conf') $Temp
    $Base = [IO.File]::ReadAllText((Join-Path $Fixture 'tool.conf'))
    foreach ($Line in Get-Content -LiteralPath (Join-Path $Fixture 'cases.tsv')) {
        if ($Line.StartsWith('#')) { continue }
        $Name, $Search, $Replacement, $Outcome, $Dependencies, $Closure, $FailureHint = $Line.Split('|')
        if (-not $Base.Contains($Search)) { throw "Fixture edit missing: $Name" }
        [IO.File]::WriteAllText((Join-Path $Temp 'tool.conf'), $Base.Replace($Search, $Replacement.Replace('\n', "`n")))
        $Failed = $false
        try { $Plan = @(Get-InstallPlan $Temp macos $false $false $false) } catch { $Failed = $true; $ParseError = $_ }
        if ($Outcome -eq 'error') {
            if (-not $Failed) { throw "Accepted invalid dependency case: $Name" }
            if ([string]$ParseError -notmatch [regex]::Escape($FailureHint)) { throw "Wrong rejection for ${Name}: $ParseError" }
            continue
        }
        if ($Failed) { throw "Rejected ${Name}: $ParseError" }
        $Tool = @($Plan | Where-Object { $_.id -eq 'tool' })[0]
        if ($Tool.depends_on -cne $Dependencies) { throw "Dependency merge mismatch: $Name" }
        $Selected = @(Select-WorkflowInstallPlan @{ install='tool' } $Plan)
        if (($Selected.id -join ' ') -cne $Closure) { throw "Profile closure mismatch: $Name" }
    }
    Copy-Item (Join-Path $Fixture 'tool.conf') (Join-Path $Temp 'tool.conf') -Force
    $Plan = @(Get-InstallPlan $Temp macos $false $false $false)
    $Tool = @($Plan | Where-Object { $_.id -eq 'tool' })[0]
    if ($Tool.install_depends_on -cne 'build-brew') { throw 'Common edge was pruned' }
    $Tool.action = 'skip'
    if ((@(Select-WorkflowInstallPlan @{install='tool'} $Plan).id -join ' ') -cne 'shared tool') { throw 'Unused recipe dependency was selected' }
    if ((@(Select-WorkflowInstallPlan @{install='tool build-brew'} $Plan).id -join ' ') -cne 'shared build-brew tool') { throw 'Explicit dependency root was pruned' }
    if (@(Select-WorkflowInstallPlan @{install='all'} $Plan).Count -ne 4) { throw 'All selection was pruned' }
    # A real matching file must avoid invoking a failing dependency probe.
    $Marker = Join-Path $Temp 'present'; Set-Content $Marker 'present'
    $Root = @{id='tool';method='winget';depends_on='runtime builder';install_depends_on='builder';discovery='manual:file:program_files:present'}
    $Runtime = @{id='runtime';method='winget';discovery='manual:file:program_files:present'}
    $Builder = @{id='builder';method='msvc';components='component'}
    $NativeFixture = New-FakeWinGet $Temp
    Copy-Item (Join-Path $NativeFixture.Bin 'winget.exe') (Join-Path $Temp 'vswhere.exe')
    Set-Content (Join-Path $NativeFixture.State 'probe-exit') 42
    $Context = @{ProgramFiles=$Temp;VsInstallerRoot=$Temp}
    $Plan = @($Builder,$Runtime,$Root)
    foreach ($Item in $Plan) {
        $Item.schema_version = Get-DataContractVersion install-plan
        $Item.action = 'install'; $Item.reason = 'requested'
    }
    if ((@(Select-WorkflowInstallPlan @{install='tool'} $Plan $Context normal).id -join ' ') -cne 'runtime tool') { throw 'Lazy discovery selected an unused builder' }
    $Code=0
    try { Select-WorkflowInstallPlan @{install='tool builder'} $Plan $Context normal } catch { $Code=Get-ExecutionExceptionCode $_.Exception }
    if ($Code -ne 42) { throw 'Explicit builder was not probed' }
    Remove-Item $Marker
    $Code=0
    try { Select-WorkflowInstallPlan @{install='tool'} $Plan $Context normal } catch { $Code=Get-ExecutionExceptionCode $_.Exception }
    if ($Code -ne 42) { throw 'Missing target did not select its builder' }
    Write-Host 'Method dependency merging, selected graphs and profile closures passed.'
} finally {
    $env:PATH = $PreviousPath; $env:DOTFILES_TEST_PACKAGE_STATE = $PreviousState
    Remove-FakeWinGetLinks $NativeFixture
    Remove-Item -LiteralPath $Temp -Recurse -Force
}
