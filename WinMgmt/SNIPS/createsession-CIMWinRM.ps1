<#
.SYNOPSIS
Retrieves IP-enabled network adapter configuration from one or more remote Windows computers using CIM over WinRM.

.DESCRIPTION
This advanced function connects to one or more remote Windows computers via a CIM session over WinRM (WSMan),
queries Win32_NetworkAdapterConfiguration for IP-enabled adapters, and returns adapter Description, MACAddress,
and IPAddress.

It supports multiple computers, optional credential prompting, input validation, and an optional reachability
pre-check to fail fast when a target is not reachable.

.WHAT THIS DOES
- Validates ComputerName input (non-empty)
- Optionally verifies reachability (WSMan and/or ICMP)
- Creates a CIM session per computer
- Queries Win32_NetworkAdapterConfiguration where IPEnabled=True
- Outputs Description, MACAddress, IPAddress plus ComputerName
- Always cleans up CIM sessions (even on errors)

.REQUIREMENTS
- PowerShell 7+ or Windows PowerShell 5.1
- WinRM enabled and accessible on remote computers
- Appropriate permissions to query CIM/WMI data remotely

.PARAMETER ComputerName
One or more target computer names (hostname or FQDN). Accepts an array and pipeline input.

.PARAMETER Credential
Credential used to authenticate the CIM session. If omitted, you can use -PromptForCredential to be prompted.

.PARAMETER Authentication
Authentication mechanism for New-CimSession. Defaults to Negotiate.

.PARAMETER PromptForCredential
Prompts for a credential if -Credential is not provided.

.PARAMETER ReachabilityCheck
If set, validates reachability before attempting CIM:
- Attempts Test-WSMan first
- Falls back to Test-Connection if WSMan test fails

.PARAMETER ConnectionTimeoutSeconds
Timeout (seconds) for reachability checks.

.PARAMETER PassThru
If set, returns the raw CIM objects (Win32_NetworkAdapterConfiguration). By default, returns a curated projection.


.EXAMPLE 1
Query a single computer and prompt for credentials:
```powershell
Get-RemoteNetworkAdapterInfo -ComputerName 'SLKRCKHP' -PromptForCredential

.EXAMPLE 2
Query multiple computers with an explicit credential:
$cred = Get-Credential
Get-RemoteNetworkAdapterInfo -ComputerName @('PC1','PC2') -Credential $cred -ReachabilityCheck

.EXAMPLE 3
Pipeline input:
'PC1','PC2' | Get-RemoteNetworkAdapterInfo -PromptForCredential -ReachabilityCheck

.OUTPUTS
By default: PSCustomObject with ComputerName, Description, MACAddress, IPAddress
With -PassThru: Microsoft.Management.Infrastructure.CimInstance (Win32_NetworkAdapterConfiguration)

.NOTES

Uses try/finally to guarantee session cleanup.

If a target is unreachable and -ReachabilityCheck is enabled, the function writes a non-terminating error and continues.

If New-CimSession fails for a target, the function writes a non-terminating error and continues.
#>

function Get-RemoteNetworkAdapterInfo {
[CmdletBinding()]
param(
[Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
[ValidateNotNullOrEmpty()]
[string[]]$ComputerName,

    [Parameter(ValueFromPipelineByPropertyName)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [ValidateSet('Default','Basic','Negotiate','Kerberos','NtlmDomain','Digest','CredSsp')]
    [string]$Authentication = 'Negotiate',

    [Parameter()]
    [switch]$PromptForCredential,

    [Parameter()]
    [switch]$ReachabilityCheck,

    [Parameter()]
    [ValidateRange(1,300)]
    [int]$ConnectionTimeoutSeconds = 5,

    [Parameter()]
    [switch]$PassThru
)

begin {
    if (-not $Credential -and $PromptForCredential) {
        $Credential = Get-Credential
    }
}

process {
    foreach ($cn in $ComputerName) {

        # Extra guard for pipeline scenarios with whitespace values
        if ([string]::IsNullOrWhiteSpace($cn)) {
            Write-Error "ComputerName cannot be empty or whitespace."
            continue
        }

        if ($ReachabilityCheck) {
            $reachable = $false

            try {
                # Prefer WSMan reachability check for WinRM scenarios
                $null = Test-WSMan -ComputerName $cn -ErrorAction Stop
                $reachable = $true
            }
            catch {
                # Fallback: ICMP ping (may be blocked; best-effort)
                try {
                    $reachable = Test-Connection -ComputerName $cn -Count 1 -Quiet -TimeoutSeconds $ConnectionTimeoutSeconds
                }
                catch {
                    $reachable = $false
                }
            }

            if (-not $reachable) {
                Write-Error "Target [$cn] is not reachable via WSMan and did not respond to ICMP ping (or ICMP is blocked). Skipping."
                continue
            }
        }

        $cimSession = $null

        try {
            $cimParams = @{
                ComputerName   = $cn
                Authentication = $Authentication
            }

            if ($Credential) {
                $cimParams.Credential = $Credential
            }

            $cimSession = New-CimSession @cimParams

            $results = Get-CimInstance -CimSession $cimSession -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"

            if ($PassThru) {
                # Return raw CIM instances (still enrich with computer name via NoteProperty)
                foreach ($r in $results) {
                    $r | Add-Member -NotePropertyName ComputerName -NotePropertyValue $cn -Force
                    $r
                }
            }
            else {
                $results | Select-Object `
                    @{ Name = 'ComputerName'; Expression = { $cn } },
                    Description,
                    MACAddress,
                    IPAddress
            }
        }
        catch {
            Write-Error "Failed querying [$cn]: $($_.Exception.Message)"
            continue
        }
        finally {
            if ($cimSession) {
                try { Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue } catch { }
            }
        }
    }
}
}