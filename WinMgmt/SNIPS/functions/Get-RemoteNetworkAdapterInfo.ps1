<#
.SYNOPSIS
Retrieves IP-enabled network adapter configuration from one or more remote Windows computers using CIM over WinRM.

.DESCRIPTION
Merged implementation that combines the benefits of:
- Script 1 (self-contained reachability check with optional ICMP fallback + inline session options)
- Script 2 (helper-based preflight/session creation/cleanup for reuse and testability)

If helper functions (Test-WinRmReady, New-WinRmCimSession, Remove-SafeCimSession) are available, they are used.
If they are not loaded, the function falls back to a self-contained implementation.

.WHAT THIS DOES
- Validates ComputerName input
- Optional reachability check:
  - Uses Test-WinRmReady if available (WSMan-first)
  - Optionally falls back to ICMP ping (Test-Connection)
- Creates CIM sessions with WSMan operation timeout
- Queries Win32_NetworkAdapterConfiguration where IPEnabled=True
- Outputs adapter details with ComputerName
- Guarantees CIM session cleanup

.REQUIREMENTS
- PowerShell 7+ or Windows PowerShell 5.1
- WinRM enabled and accessible on target computers
- Appropriate permissions to query CIM/WMI data remotely

.PARAMETER ComputerName
One or more target computer names (hostname or FQDN). Accepts arrays and pipeline input.

.PARAMETER Credential
Credential used for CIM authentication.

.PARAMETER PromptForCredential
Prompts for credentials if -Credential is not supplied.

.PARAMETER Authentication
Authentication mechanism for New-CimSession. Defaults to Negotiate.

.PARAMETER ReachabilityCheck
If specified, validates WSMan readiness before attempting CIM.

.PARAMETER AllowIcmpFallback
If specified (and ReachabilityCheck is enabled), attempts ICMP ping when WSMan checks fail.

.PARAMETER ConnectionTimeoutSeconds
Timeout (seconds) for ICMP reachability checks.

.PARAMETER WsmanOperationTimeoutSeconds
Timeout (seconds) for WSMan/CIM operations.

.PARAMETER PassThru
Returns raw CIM objects instead of projected output.

.EXAMPLE
Query a single computer and prompt for credentials.
Get-RemoteNetworkAdapterInfo -ComputerName 'SLKRCKHP' -PromptForCredential

.EXAMPLE
Query multiple computers with increased WSMan timeout.
$cred = Get-Credential
Get-RemoteNetworkAdapterInfo -ComputerName @('PC1','PC2') -Credential $cred -ReachabilityCheck -WsmanOperationTimeoutSeconds 60

.EXAMPLE
Allow ICMP fallback when WSMan readiness fails.
Get-RemoteNetworkAdapterInfo -ComputerName 'PC1' -ReachabilityCheck -AllowIcmpFallback -ConnectionTimeoutSeconds 3

.OUTPUTS
By default:
ComputerName, Description, MACAddress, IPAddress

With -PassThru:
Microsoft.Management.Infrastructure.CimInstance (Win32_NetworkAdapterConfiguration)

.NOTES
- Uses helper functions when available:
  - Test-WinRmReady
  - New-WinRmCimSession
  - Remove-SafeCimSession
- Falls back to direct New-CimSession/Remove-CimSession when helpers are not present.

.LINK
https://learn.microsoft.com/windows/win32/cimwin32prov/win32-networkadapterconfiguration
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
        [switch]$PromptForCredential,

        [Parameter()]
        [ValidateSet('Default','Basic','Negotiate','Kerberos','NtlmDomain','Digest','CredSsp')]
        [string]$Authentication = 'Negotiate',

        [Parameter()]
        [switch]$ReachabilityCheck,

        [Parameter()]
        [switch]$AllowIcmpFallback,

        [Parameter()]
        [ValidateRange(1,300)]
        [int]$ConnectionTimeoutSeconds = 5,

        [Parameter()]
        [ValidateRange(5,600)]
        [int]$WsmanOperationTimeoutSeconds = 30,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        if (-not $Credential -and $PromptForCredential) {
            $Credential = Get-Credential
        }

        $hasTestWinRmReady   = [bool](Get-Command Test-WinRmReady -ErrorAction SilentlyContinue)
        $hasNewWinRmCimSess  = [bool](Get-Command New-WinRmCimSession -ErrorAction SilentlyContinue)
        $hasRemoveSafeCim    = [bool](Get-Command Remove-SafeCimSession -ErrorAction SilentlyContinue)

        # Self-contained session option for fallback mode
        $fallbackSessionOption = New-CimSessionOption -Protocol Wsman -OperationTimeoutSec $WsmanOperationTimeoutSeconds
    }

    process {
        foreach ($cn in $ComputerName) {

            if ([string]::IsNullOrWhiteSpace($cn)) {
                Write-Error "ComputerName cannot be empty or whitespace."
                continue
            }

            if ($ReachabilityCheck) {
                $wsmanOk = $false
                $wsmanErr = $null

                if ($hasTestWinRmReady) {
                    $pre = Test-WinRmReady -ComputerName $cn -SkipTcpPortTest
                    $wsmanOk  = [bool]$pre.WsmanOk
                    $wsmanErr = $pre.WsmanError
                }
                else {
                    try {
                        Test-WSMan -ComputerName $cn -ErrorAction Stop | Out-Null
                        $wsmanOk = $true
                    }
                    catch {
                        $wsmanOk = $false
                        $wsmanErr = $_.Exception.Message
                    }
                }

                if (-not $wsmanOk) {
                    if ($AllowIcmpFallback) {
                        $icmpOk = $false
                        try {
                            $icmpOk = Test-Connection -ComputerName $cn -Count 1 -Quiet -TimeoutSeconds $ConnectionTimeoutSeconds
                        }
                        catch {
                            $icmpOk = $false
                        }

                        if (-not $icmpOk) {
                            Write-Error "Target [$cn] is not WSMan-ready and ICMP fallback failed. WSMan error: $wsmanErr"
                            continue
                        }
                        # ICMP succeeded; proceed (WSMan might still fail at session creation; we will catch/continue)
                    }
                    else {
                        Write-Error "Target [$cn] is not WSMan-ready: $wsmanErr"
                        continue
                    }
                }
            }

            $session = $null

            try {
                if ($hasNewWinRmCimSess) {
                    $session = New-WinRmCimSession -ComputerName $cn -Credential $Credential -Authentication $Authentication -WsmanOperationTimeoutSeconds $WsmanOperationTimeoutSeconds
                }
                else {
                    $cimParams = @{
                        ComputerName   = $cn
                        Authentication = $Authentication
                        SessionOption  = $fallbackSessionOption
                        ErrorAction    = 'Stop'
                    }
                    if ($Credential) { $cimParams.Credential = $Credential }

                    $session = New-CimSession @cimParams
                }

                if (-not $session) {
                    throw "Failed to create CIM session for [$cn] (session is null)."
                }

                $results = Get-CimInstance -CimSession $session -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction Stop

                if ($PassThru) {
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
            }
            finally {
                if ($hasRemoveSafeCim) {
                    Remove-SafeCimSession -CimSession $session
                }
                else {
                    if ($session) {
                        try { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue } catch { }
                    }
                }
            }
        }
    }
}