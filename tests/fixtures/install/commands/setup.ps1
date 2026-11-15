function New-FakeWinGet {
    param([string]$Directory)
    $Bin = Join-Path $Directory 'bin'; $State = Join-Path $Directory 'state'
    $null = New-Item -ItemType Directory $Bin, $State
    $Target = Join-Path $Bin 'winget.exe'
    if ($env:OS -eq 'Windows_NT') {
        # Compile a real native-launchable fixture with the Windows .NET Framework compiler.
        $Compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        if (-not (Test-Path -LiteralPath $Compiler)) { $Compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
        & $Compiler /nologo /target:exe "/out:$Target" (Join-Path $PSScriptRoot 'fake-winget.cs')
        if ($LASTEXITCODE -ne 0) { throw 'Failed to compile fake WinGet' }
    } else {
        Copy-Item (Join-Path $PSScriptRoot 'fake-package-command.sh') $Target
        & /bin/chmod +x $Target
        foreach ($Name in @('bash','cat','grep','touch','sleep')) {
            $Source = (Get-Command $Name -CommandType Application | Select-Object -First 1).Source
            $null = New-Item -ItemType SymbolicLink -Path (Join-Path $Bin $Name) -Target $Source
        }
    }
    $env:DOTFILES_TEST_PACKAGE_STATE = $State
    $env:PATH = $Bin
    @{ Bin=$Bin; State=$State }
}
