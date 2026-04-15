# FILE: WinMgmt\SNIPS\functions\Test-HostReachable.ps1
<#
.SYNOPSIS
Performs lightweight reachability checks (DNS, ICMP, and optional TCP port) for one or more hosts.

.DESCRIPTION
Test-HostReachable provides a consistent, scriptable way to validate whether a target host is reachable.
It can perform:
- DNS resolution (best-effort)
- ICMP ping (best-effort; may be blocked)
- TCP port connect test (optional; useful for WinRM 5985/5986)

It returns a structured object per ComputerName so wrapper scripts and other functions can make decisions
without parsing strings.

.WHAT THIS DOES
- Validates input
- Optionally resolves DNS
- Optionally pings the host
- Optionally tests a TCP port
- Returns a result object per host

.REQUIREMENTS
- PowerShell 7+ or Windows PowerShell 5.1
- Network access to target(s)

.PARAMETER ComputerName
One or more hostnames/FQDNs/IPs. Accepts arrays and pipeline input.

.PARAMETER TestDns
If set, attempts DNS resolution.

.PARAMETER TestIcmp
If set, attempts an ICMP ping using Test-Connection (may be blocked).

.PARAMETER TcpPort
If set, attempts a TCP connect test to the specified port.

.PARAMETER TimeoutSeconds
Timeout for ICMP and TCP checks.

.EXAMPLE
Test DNS + ICMP for two hosts.
Test-HostReachable -ComputerName @('PC1','PC2') -TestDns -TestIcmp

.EXAMPLE
Test WinRM port reachability (HTTP).
Test-HostReachable -ComputerName 'SERVER01' -TcpPort 5985 -TimeoutSeconds 3

.OUTPUTS
PSCustomObject with properties:
ComputerName, DnsResolved, DnsAddresses, IcmpReachable, TcpPort, TcpPortOpen, Notes

.NOTES
- ICMP may be blocked by firewalls; a failed ping does not guarantee the host is down.
- TCP port test uses System.Net.Sockets.TcpClient.

#>
function Test-HostReachable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter()]
        [switch]$TestDns,

        [Parameter()]
        [switch]$TestIcmp,

        [Parameter()]
        [ValidateRange(1,65535)]
        [int]$TcpPort,

        [Parameter()]
        [ValidateRange(1,300)]
        [int]$TimeoutSeconds = 3
    )

    process {
        foreach ($cn in $ComputerName) {
            if ([string]::IsNullOrWhiteSpace($cn)) {
                Write-Error "ComputerName cannot be empty or whitespace."
                continue
            }

            $dnsResolved   = $null
            $dnsAddresses  = @()
            $icmpReachable = $null
            $tcpPortOpen   = $null
            $notes         = @()

            if ($TestDns) {
                try {
                    # Prefer Resolve-DnsName if available; fallback to .NET DNS
                    if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
                        $dns = Resolve-DnsName -Name $cn -ErrorAction Stop |
                            Where-Object { $_.IPAddress } |
                            Select-Object -ExpandProperty IPAddress -Unique
                        $dnsAddresses = @($dns)
                    }
                    else {
                        $dnsAddresses = @([System.Net.Dns]::GetHostAddresses($cn) | ForEach-Object { $_.IPAddressToString } | Select-Object -Unique)
                    }

                    $dnsResolved = ($dnsAddresses.Count -gt 0)
                }
                catch {
                    $dnsResolved = $false
                    $notes += "DNS resolution failed: $($_.Exception.Message)"
                }
            }

            if ($TestIcmp) {
                try {
                    $icmpReachable = Test-Connection -ComputerName $cn -Count 1 -Quiet -TimeoutSeconds $TimeoutSeconds
                }
                catch {
                    $icmpReachable = $false
                    $notes += "ICMP test failed: $($_.Exception.Message)"
                }
            }

            if ($PSBoundParameters.ContainsKey('TcpPort')) {
                $client = $null
                try {
                    $client = [System.Net.Sockets.TcpClient]::new()
                    $iar = $client.BeginConnect($cn, $TcpPort, $null, $null)
                    $completed = $iar.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
                    if (-not $completed) {
                        $tcpPortOpen = $false
                        $notes += "TCP connect timed out."
                    }
                    else {
                        $client.EndConnect($iar)
                        $tcpPortOpen = $true
                    }
                }
                catch {
                    $tcpPortOpen = $false
                    $notes += "TCP connect failed: $($_.Exception.Message)"
                }
                finally {
                    try { $client?.Close() } catch { }
                }
            }

            [pscustomobject]@{
                ComputerName  = $cn
                DnsResolved   = $dnsResolved
                DnsAddresses  = $dnsAddresses
                IcmpReachable = $icmpReachable
                TcpPort       = if ($PSBoundParameters.ContainsKey('TcpPort')) { $TcpPort } else { $null }
                TcpPortOpen   = $tcpPortOpen
                Notes         = if ($notes.Count) { $notes -join ' | ' } else { $null }
            }
        }
    }
}
