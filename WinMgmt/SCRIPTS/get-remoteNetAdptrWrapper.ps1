<#
.SYNOPSIS
Interactive wrapper script for Get-RemoteNetworkAdapterInfo.

.DESCRIPTION
This script prompts the user for one or more computer names and credentials,
then invokes the Get-RemoteNetworkAdapterInfo advanced function to retrieve
IP-enabled network adapter information via CIM over WinRM.

This wrapper is intended for interactive use and delegates all core logic
to the underlying function.

.WHAT THIS DOES
- Prompts for target computer name(s)
- Prompts for credentials
- Calls Get-RemoteNetworkAdapterInfo
- Displays formatted results

.REQUIREMENTS
- PowerShell 7+ or Windows PowerShell 5.1
- WinRM enabled and accessible on target computers
- Get-RemoteNetworkAdapterInfo function available (dot-sourced or imported)

.EXAMPLE
Run the script and follow prompts.
.\Invoke-RemoteNetworkAdapterInfo.ps1

.NOTES
- This script is a thin wrapper by design
- All validation and error handling occurs in the function

.LINK
https://learn.microsoft.com/windows/win32/cimwin32prov/win32-networkadapterconfiguration
#>

# --- Load function (adjust path if needed) ---
$functionPath = Join-Path $PSScriptRoot '..\SNIPS\functions\Get-RemoteNetworkAdapterInfo.ps1'
if (-not (Test-Path $functionPath)) {
    throw "Required function file not found: $functionPath"
}
. $functionPath

# --- Prompt for input ---
$computerInput = Read-Host "Enter one or more computer names (comma-separated)"
$computerNames = $computerInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

if (-not $computerNames) {
    Write-Error "No valid computer names provided."
    return
}

$cred = Get-Credential

# --- Execute ---
Get-RemoteNetworkAdapterInfo `
    -ComputerName $computerNames `
    -Credential $cred `
    -ReachabilityCheck
