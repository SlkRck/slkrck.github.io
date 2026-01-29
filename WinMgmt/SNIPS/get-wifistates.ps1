<#
.SYNOPSIS
    Collects sleep, wake, and Wi-Fi adapter diagnostics from a local or remote Windows system.

.DESCRIPTION
    This script gathers diagnostic information related to system sleep states and wake behavior,
    with a focus on Wi-Fi adapters. The user is prompted for a target computer name at runtime.
    If no computer name is provided, the script runs locally.

    The script enumerates supported sleep modes, devices capable of waking the system,
    devices currently armed for wake events, and basic Wi-Fi adapter status.

.REQUIREMENTS
    - PowerShell 5.1 or later
    - WinRM enabled for remote execution
    - Administrative privileges on the target system

.EXAMPLE
    # Run the script and target a remote machine
    .\Get-WiFiSleepDiagnostics.ps1
    Enter computer name (leave blank for local): <COMPUTER01>

.EXAMPLE
    # Run the script locally
    .\Get-WiFiSleepDiagnostics.ps1
    Enter computer name (leave blank for local): [Enter]

.NOTES
    This is a read-only diagnostic script and makes no configuration changes.
#>

$computerName = Read-Host "Enter computer name (leave blank for local)"

if ([string]::IsNullOrWhiteSpace($computerName)) {
    $computerName = $env:COMPUTERNAME
}

$scriptBlock = {
    Write-Host "=== Supported Sleep States ==="
    powercfg /a

    Write-Host "`n=== Devices Capable of Waking the System ==="
    powercfg /devicequery wake_from_any

    Write-Host "`n=== Devices Currently Armed for Wake ==="
    powercfg /devicequery wake_armed

    Write-Host "`n=== Wi-Fi Adapter Info ==="
    Get-NetAdapter -Name Wi-Fi |
        Select-Object Name, InterfaceDescription, Status
}

if ($computerName -eq $env:COMPUTERNAME) {
    & $scriptBlock
}
else {
    $cred = Get-Credential
    Invoke-Command -ComputerName $computerName -Credential $cred -ScriptBlock $scriptBlock
}
