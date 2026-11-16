$DotfilesPythonLauncher = Join-Path $PSScriptRoot '../dotfiles_core/launch.py'

function Initialize-DotfilesPython {
    if ($script:DotfilesPythonExecutable) { return }
    $Selected = if (Test-Path Env:DOTFILES_PYTHON) { $env:DOTFILES_PYTHON } elseif ($env:OS -eq 'Windows_NT') {
        Join-Path $PSScriptRoot '../.venv/Scripts/python.exe'
    } else { Join-Path $PSScriptRoot '../.venv/bin/python' }
    if (-not $Selected) { throw 'DOTFILES_PYTHON must name one interpreter' }
    $Resolved = Get-Command -Name $Selected -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $Resolved) { throw "Python interpreter unavailable: $Selected" }
    $Executable = [IO.Path]::GetFullPath($Resolved.Source)
    & $Executable -X utf8 -B $DotfilesPythonLauncher runtime-check | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Python >=3.14 and declared dependencies must be prepared before invocation' }
    $script:DotfilesPythonExecutable = $Executable
    $env:DOTFILES_PYTHON = $Executable
}

function Invoke-DotfilesPython {
    param([string[]]$Arguments)
    Initialize-DotfilesPython
    $SavedEncoding = [Console]::OutputEncoding
    $SavedPython = $env:DOTFILES_PYTHON
    # Windows PowerShell 5.1 turns native stderr into ErrorRecords. The caller
    # must receive the diagnostics and inspect the process exit code itself.
    $ErrorActionPreference = 'Continue'
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $env:DOTFILES_PYTHON = $script:DotfilesPythonExecutable
        & $script:DotfilesPythonExecutable -X utf8 -B $DotfilesPythonLauncher @Arguments
    } finally {
        [Console]::OutputEncoding = $SavedEncoding
        if ($null -eq $SavedPython) { Remove-Item Env:DOTFILES_PYTHON -ErrorAction SilentlyContinue }
        else { $env:DOTFILES_PYTHON = $SavedPython }
    }
}

# Pure-rule bridge. Values remain literal argv entries, including empty strings
# on Windows PowerShell 5.1; stdout is structured data, not executable text.
function Invoke-DotfilesRule {
    param([string]$Operation, [hashtable]$Options = @{}, [switch]$AsHashtable)
    $Arguments = @($Operation, '--json')
    foreach ($Key in $Options.Keys) { $Arguments += "--$Key=$($Options[$Key])" }
    $Output = @(Invoke-DotfilesPython -Arguments $Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ($Output -join "`n") }
    $Value = ($Output -join "`n") | ConvertFrom-Json
    if ($AsHashtable) {
        $Result = @{}
        foreach ($Property in $Value.PSObject.Properties) { $Result[$Property.Name] = $Property.Value }
        return $Result
    }
    $Value
}

function Invoke-DotfilesRequest {
    param([string]$Operation, [hashtable]$Context = @{}, [switch]$Stream)
    $ErrorActionPreference = 'Stop'
    Initialize-DotfilesPython
    $Temporary = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-core-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $Temporary
    try {
        if ($env:OS -ne 'Windows_NT') { & /bin/chmod 700 $Temporary; if ($LASTEXITCODE) { throw 'Cannot protect core request directory' } }
        else {
            $Acl = [Security.AccessControl.DirectorySecurity]::new()
            $Acl.SetAccessRuleProtection($true, $false)
            $Identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
            $Rule = [Security.AccessControl.FileSystemAccessRule]::new($Identity, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
            $Acl.AddAccessRule($Rule)
            Set-Acl -LiteralPath $Temporary -AclObject $Acl
        }
        $RequestPath = Join-Path $Temporary 'request.json'
        $ResultPath = Join-Path $Temporary 'result.json'
        $Request = @{ protocol_version=1;operation=$Operation;context=$Context }
        [IO.File]::WriteAllText($RequestPath, (ConvertTo-Json -InputObject $Request -Depth 32 -Compress), [Text.UTF8Encoding]::new($false))
        if ($Stream) {
            Invoke-DotfilesPython -Arguments @('core-request','--request',$RequestPath,'--result',$ResultPath) | ForEach-Object { Write-Host $_ }
        } else {
            $null = Invoke-DotfilesPython -Arguments @('core-request','--request',$RequestPath,'--result',$ResultPath)
        }
        $Code = $LASTEXITCODE
        # Reuse the strict decoder, including duplicate-key rejection. Native
        # ConvertFrom-Json alone accepts some damaged envelopes on older hosts.
        $Diagnostic = @(Invoke-DotfilesPython -Arguments @('core-result','--result',$ResultPath,'--expected-operation',$Operation,'--code',[string]$Code,'--verify-only') 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $Exception = [Exception]::new(($Diagnostic -join "`n"))
            $Exception.Data['ExitCode'] = $LASTEXITCODE
            throw $Exception
        }
        $Result = [IO.File]::ReadAllText($ResultPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($null -eq $Result.data.PSObject.Properties['value']) { throw 'Missing core result value' }
        $Result.data.value
    } finally { Remove-Item -LiteralPath $Temporary -Recurse -Force }
}

function ConvertTo-DotfilesRecord {
    param($Value)
    $Record = @{}
    foreach ($Property in $Value.PSObject.Properties) { $Record[$Property.Name] = $Property.Value }
    $Record
}
