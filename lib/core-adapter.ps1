param([string]$RequestPath, [string]$ResultPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'python.ps1')
Initialize-DotfilesPython
$PayloadPath = "$ResultPath.payload"
$null = Invoke-DotfilesPython -Arguments @('native-input','--platform','windows','--request',$RequestPath,'--payload',$PayloadPath)
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$Request = [IO.File]::ReadAllText($RequestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$Code = 0
try {
    if ($Request.operation -ceq 'apply-restore') {
        . (Join-Path $PSScriptRoot 'apply-items.ps1')
        Restore-ApplyJournalUnlocked ([string]$Request.context.journal) ([bool]$Request.context.dry)
    } elseif ($Request.operation -ceq 'apply-effect') {
        . (Join-Path $PSScriptRoot 'apply-items.ps1')
        $Path = [string]$Request.context.path
        switch -CaseSensitive ($Request.context.action) {
            start {
                if (Get-ApplyEntry $Path) { throw 'Apply session already exists' }
                New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null
                '{"version":1}' | Set-Content -LiteralPath (Join-Path $Path 'journal.jsonl') -Encoding UTF8
            }
            transaction {
                $Operation = @(ConvertFrom-ApplyRecords @($Request.context.row))[0]
                Invoke-ApplyTransaction $Operation $Path ([int]$Request.context.sequence)
            }
            preview {
                $Row = $Request.context.row
                if ($Row.backup) { Write-Host "DRY RUN: back up $($Row.target) to $($Row.backup)" }
                Write-Host "DRY RUN: $($Row.action) $($Row.source) -> $($Row.target)"
            }
            default { throw 'Unsupported apply effect' }
        }
    } elseif ($Request.operation -ceq 'workflow-query') {
        . (Join-Path $PSScriptRoot 'workflow.ps1')
        . (Join-Path $PSScriptRoot 'workflow-observation.ps1')
        $Context = ConvertTo-DotfilesRecord $Request.context.native_context
        $Payload = @(Invoke-NativeWorkflowQuery -Query $Request.context.query -Arguments @($Request.context.arguments) -Context $Context) -join "`n"
        [IO.File]::WriteAllText($PayloadPath, $Payload, [Text.UTF8Encoding]::new($false))
    } elseif ($Request.operation -ceq 'workflow-stage') {
        . (Join-Path $PSScriptRoot 'workflow.ps1')
        $Context = ConvertTo-DotfilesRecord $Request.context.native_context
        foreach ($Key in @('Profile', 'InstallContext', 'WslPlan')) {
            if ($Context[$Key]) { $Context[$Key] = ConvertTo-DotfilesRecord $Context[$Key] }
        }
        $Actions = Get-WindowsWorkflowActions
        $Writer = [IO.File]::CreateText([string]$Request.context.log)
        $Writer.AutoFlush = $true
        $StageCode = 0; $Reason = ''
        try {
            & $Actions[$Request.context.action] $Context ([string]$Request.context.report) ([string]$Request.context.metadata) *>&1 | ForEach-Object {
                $Line = $_.ToString()
                $Writer.WriteLine($Line)
                Write-Host $Line
            }
        } catch {
            $StageCode = Get-ExecutionExceptionCode $_.Exception
            $Reason = $_.Exception.Message
            $Writer.WriteLine($Reason)
            Write-Warning $Reason
        } finally { $Writer.Dispose() }
        [IO.File]::WriteAllText($PayloadPath, (ConvertTo-Json -Compress @{exit_code=$StageCode;reason=$Reason}), [Text.UTF8Encoding]::new($false))
    } elseif ($Request.operation -ceq 'apply-query') {
        . (Join-Path $PSScriptRoot 'apply-fs.ps1')
        $Path = [string]$Request.context.path
        $Other = [string]$Request.context.other
        $Payload = switch -CaseSensitive ($Request.context.query) {
            entry {
                $Entry = Get-ApplyEntry $Path
                $Kind = if (-not $Entry) { 'absent' } elseif (Test-ApplyLink $Entry) { 'link' } elseif ($Entry.PSIsContainer) { 'directory' } else { 'file' }
                ConvertTo-Json -Compress @{kind=$Kind;readable=$false;writable=$false;searchable=$false}
            }
            exists { [string][int][bool](Get-ApplyEntry $Path) }
            file { [string][int](Test-Path -LiteralPath $Path -PathType Leaf) }
            readonly { $Entry = Get-ApplyEntry $Path; [string][int][bool]($Entry -and $Entry.IsReadOnly) }
            state { Get-ApplyState $Path }
            tree { (@(Get-ApplyTree $Path) | ForEach-Object { $_.FullName }) -join "`n" }
            anchor { Get-ApplyAnchor $Path }
            'resolve-root' { Resolve-ApplyRoot $Path }
            identity { Get-ApplyIdentity $Path }
            equal-copy { [string][int]((Get-ApplyContent $Path) -eq (Get-ApplyContent $Other)) }
            equal-hardlink { [string][int]((Get-ApplyIdentity $Path) -eq (Get-ApplyIdentity $Other)) }
            default { throw 'Unsupported native apply query' }
        }
        [IO.File]::WriteAllText($PayloadPath, [string]$Payload, [Text.UTF8Encoding]::new($false))
    } elseif ($Request.operation -ceq 'publish-report') {
        . (Join-Path $PSScriptRoot 'atomic-report.ps1')
        Write-AtomicReport $Request.context.path $Request.context.text -CreateNew:($Request.context.mode -ceq 'create')
    } else {
        . (Join-Path $PSScriptRoot 'install-items.ps1')
        $script:DotfilesExecutionPolicyPath = [string]$Request.context.policy_path
        $Context = ConvertTo-DotfilesRecord $Request.context.native_context
        if ($Request.operation -cne 'discovery-path') { $Item = ConvertTo-DotfilesRecord $Request.context.item }
        if ($Request.operation -ceq 'discovery-path') {
            $Path = [string](Resolve-InstallDiscoveryPath $Request.context.kind $Request.context.root $Request.context.relative $Context)
            [IO.File]::WriteAllText($PayloadPath, (ConvertTo-Json -InputObject $Path -Compress), [Text.UTF8Encoding]::new($false))
        } elseif ($Request.operation -ceq 'install-state') {
            $State = Get-NativeInstallState $Item $Context
            [IO.File]::WriteAllText($PayloadPath, [string]$State, [Text.UTF8Encoding]::new($false))
        } elseif ($Request.operation -ceq 'install-command-probe') {
            $Present = [int][bool]($Item.probe_command -and (Get-Command $Item.probe_command -ErrorAction SilentlyContinue))
            [IO.File]::WriteAllText($PayloadPath, [string]$Present, [Text.UTF8Encoding]::new($false))
        } elseif ($Request.operation -ceq 'install-target-check') {
            throw 'Target check is Unix-only'
        } elseif ($Request.operation -ceq 'install-command') {
            $Context.Method = $Item.method
            switch -CaseSensitive ($Item.method) {
                'font-download' { Install-WindowsFontItem -Item $Item -Context $Context }
                winget { Install-WinGetItem -Item $Item -Context $Context }
                msvc { Install-MsvcItem -Item $Item -Context $Context }
                default { throw "Unsupported Windows handler: $($Item.method)" }
            }
        } else { throw 'Unsupported native operation' }
    }
} catch {
    $Code = if (Get-Command Get-ExecutionExceptionCode -ErrorAction SilentlyContinue) { Get-ExecutionExceptionCode $_.Exception } else { 1 }
    Write-Warning $_.Exception.Message
}
$null = Invoke-DotfilesPython -Arguments @('native-result','--platform','windows','--request',$RequestPath,'--result',$ResultPath,'--payload',$PayloadPath,'--code',[string]$Code)
if ($LASTEXITCODE) { exit 65 }
exit $Code
