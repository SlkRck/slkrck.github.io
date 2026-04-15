# FILE: WinMgmt\PesterTests\WinMgmt.StarterSet.Tests.ps1
#requires -Version 7.0
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
Pester tests for the WinMgmt starter set functions.

.DESCRIPTION
Validates logic for the starter set without requiring network access by mocking external cmdlets:
- Test-WSMan
- Test-Connection
- New-CimSession
- Get-CimInstance
- Remove-CimSession

.WHAT THIS DOES
- Dot-sources the function files
- Uses mocks to validate call patterns and outcomes
- Verifies multi-computer support and preflight gating

.REQUIREMENTS
- Pester 5+

.EXAMPLE
Invoke-Pester -Path .\WinMgmt\PesterTests -CI

.NOTES
- Update $FunctionRoot if your repo layout differs.

#>
BeforeAll {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $FunctionRoot = Join-Path $PSScriptRoot '..\SNIPS\functions'

    . (Join-Path $FunctionRoot 'Test-HostReachable.ps1')
    . (Join-Path $FunctionRoot 'Test-WinRmReady.ps1')
    . (Join-Path $FunctionRoot 'Remove-SafeCimSession.ps1')
    . (Join-Path $FunctionRoot 'New-WinRmCimSession.ps1')
    . (Join-Path $FunctionRoot 'Assert-RunningAsAdmin.ps1')
    . (Join-Path $FunctionRoot 'Get-RemoteNetworkAdapterInfo.ps1')
}

Describe 'WinMgmt Starter Set' {

    Context 'Assert-RunningAsAdmin' {
        It 'throws when not elevated (mocked via Test-IsAdministrator)' {
            Mock Test-IsAdministrator { return $false }
            { Assert-RunningAsAdmin } | Should -Throw
        }

        It 'does not throw when elevated (mocked via Test-IsAdministrator)' {
            Mock Test-IsAdministrator { return $true }
            { Assert-RunningAsAdmin } | Should -Not -Throw
        }
    }

    Context 'New-WinRmCimSession / Remove-SafeCimSession' {
        It 'creates a CIM session (mocked New-CimSession) and removes it safely' {
            Mock New-CimSession { return 'FakeSession' }
            Mock Remove-CimSession { }

            $s = New-WinRmCimSession -ComputerName 'PC1'
            $s | Should -Be 'FakeSession'

            Remove-SafeCimSession -CimSession $s
            Assert-MockCalled Remove-CimSession -Times 1 -Exactly
        }
    }

    Context 'Test-WinRmReady' {
        It 'returns WsmanOk true when Test-WSMan succeeds' {
            Mock Test-WSMan { return $true }
            Mock Test-HostReachable { [pscustomobject]@{ TcpPortOpen = $true } }

            $r = Test-WinRmReady -ComputerName 'PC1'
            $r.WsmanOk | Should -BeTrue
        }

        It 'returns WsmanOk false when Test-WSMan fails' {
            Mock Test-WSMan { throw 'no wsman' }
            Mock Test-HostReachable { [pscustomobject]@{ TcpPortOpen = $false } }

            $r = Test-WinRmReady -ComputerName 'PC1'
            $r.WsmanOk | Should -BeFalse
            $r.WsmanError | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Get-RemoteNetworkAdapterInfo' {
        BeforeEach {
            Mock Test-WSMan { return $true }
            Mock New-CimSession { return 'FakeSession' }
            Mock Remove-CimSession { }
            Mock Get-CimInstance {
                @(
                    [pscustomobject]@{
                        Description = 'Intel NIC'
                        MACAddress  = 'AA-BB-CC-DD-EE-FF'
                        IPAddress   = @('10.0.0.10')
                    }
                )
            }
        }

        It 'returns projected objects by default with ComputerName populated' {
            $r = Get-RemoteNetworkAdapterInfo -ComputerName 'PC1' -ReachabilityCheck
            $r | Should -Not -BeNullOrEmpty
            $r[0].ComputerName | Should -Be 'PC1'
            $r[0].Description  | Should -Be 'Intel NIC'
        }

        It 'supports multiple computer names and queries each computer' {
            $null = Get-RemoteNetworkAdapterInfo -ComputerName @('PC1','PC2') -ReachabilityCheck

            Assert-MockCalled New-CimSession   -Times 2 -Exactly
            Assert-MockCalled Get-CimInstance  -Times 2 -Exactly
            Assert-MockCalled Remove-CimSession -Times 2 -Exactly
        }

        It 'skips targets that are not WSMan-ready when ReachabilityCheck is enabled' {
            Mock Test-WSMan { throw 'wsman failed' }

            $r = Get-RemoteNetworkAdapterInfo -ComputerName 'PC1' -ReachabilityCheck -ErrorAction SilentlyContinue
            $r | Should -BeNullOrEmpty

            Assert-MockCalled New-CimSession  -Times 0 -Exactly
            Assert-MockCalled Get-CimInstance -Times 0 -Exactly
        }
    }
}
