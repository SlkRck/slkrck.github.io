# FILE: WinMgmt\SCRIPTS\Invoke-WinMgmtStarterSetSmokeTest.ps1
<#
.SYNOPSIS
Interactive smoke test runner for the WinMgmt starter set.

.DESCRIPTION
Prompts for one or more computer names and optionally credentials, then runs a simple inventory
query using Get-RemoteNetworkAdapterInfo. This is intended as an operator entrypoint script.

.WHAT THIS DOES
- Loads the starter set functions via dot-sourcing
- Prompts for computer names
- Prompts for credentials
- Runs Get-RemoteNetworkAdapterInfo with WSMan preflight

.REQUIREMENTS
- PowerShell 7+ recommended
- WinRM enabled on targets
- Starter set functions present in WinMgmt\SNIPS\functions

.EXAMPLE
.\Invoke-WinMgmtStarterSetSmokeTest.ps1

.NOTES
- This script is intentionally thin and delegates logic to functions.

#>
$FunctionRoot = Join-Path $PSScriptRoot '..\SNIPS\functions'

. (Join-Path $FunctionRoot 'Test-HostReachable.ps1')
. (Join-Path $FunctionRoot 'Test-WinRmReady.ps1')
. (Join-Path $FunctionRoot 'Remove-SafeCimSession.ps1')
. (Join-Path $FunctionRoot 'New-WinRmCimSession.ps1')
. (Join-Path $FunctionRoot 'Assert-RunningAsAdmin.ps1')
. (Join-Path $FunctionRoot 'Get-RemoteNetworkAdapterInfo.ps1')

$computerInput = Read-Host "Enter one or more computer names (comma-separated)"
$computerNames = $computerInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

if (-not $computerNames) {
    Write-Error "No valid computer names provided."
    exit 1
}

$useCred = Read-Host "Use explicit credentials? (Y/N)"
$cred = $null
if ($useCred -match '^(Y|y)') {
    $cred = Get-Credential
}

Get-RemoteNetworkAdapterInfo -ComputerName $computerNames -Credential $cred -ReachabilityCheck -WsmanOperationTimeoutSeconds 60
