# FILE: WinMgmt\SNIPS\functions\Test-WinRmReady.ps1
<#
.SYNOPSIS
Validates whether WinRM/WSMan is reachable on one or more computers.

.DESCRIPTION
Test-WinRmReady performs a WSMan reachability check using Test-WSMan and (optionally) a TCP port check.
It returns a structured result object per computer to enable reliable preflight gating.

.WHAT THIS DOES
- Validates input
- Attempts Test-WSMan
- Optionally tests TCP port 5985/5986
- Returns a result object per host

.REQUIREMENTS
- PowerShell 7+ or Windows PowerShell 5.1
- WSMan cmdlets available (Test-WSMan)
- Network access to target(s)

.PARAMETER ComputerName
One or more target computers. Accepts arrays and pipeline input.

.PARAMETER UseHttps
If set, checks HTTPS (5986). Otherwise checks HTTP (5985).

.PARAMETER TimeoutSeconds
Timeout for optional TCP checks.

.PARAMETER SkipTcpPortTest
If set, does not perform the TCP port test.

.EXAMPLE
Test WinRM readiness over HTTP.
Test-WinRmReady -ComputerName 'SERVER01'

.EXAMPLE
Test WinRM readiness over HTTPS.
Test-WinRmReady -ComputerName 'SERVER01' -UseHttps

.OUTPUTS
PSCustomObject with properties:
ComputerName, WsmanOk, WsmanError, TcpPort, TcpPortOpen

.NOTES
- Test-WSMan is the authoritative check for WSMan reachability.
- TCP port test is best-effort and can help troubleshoot firewall issues.

#>
function Test-WinRmReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter()]
        [switch]$UseHttps,

        [Parameter()]
        [ValidateRange(1,300)]
        [int]$TimeoutSeconds = 3,

        [Parameter()]
        [switch]$SkipTcpPortTest
    )

    process {
        foreach ($cn in $ComputerName) {
            if ([string]::IsNullOrWhiteSpace($cn)) {
                Write-Error "ComputerName cannot be empty or whitespace."
                continue
            }

            $wsmanOk    = $false
            $wsmanError = $null
            $tcpPort    = if ($UseHttps) { 5986 } else { 5985 }
            $tcpOpen    = $null

            try {
                Test-WSMan -ComputerName $cn -UseSSL:$UseHttps -ErrorAction Stop | Out-Null
                $wsmanOk = $true
            }
            catch {
                $wsmanOk = $false
                $wsmanError = $_.Exception.Message
            }

            if (-not $SkipTcpPortTest) {
                $tcpResult = Test-HostReachable -ComputerName $cn -TcpPort $tcpPort -TimeoutSeconds $TimeoutSeconds
                $tcpOpen = $tcpResult.TcpPortOpen
            }

            [pscustomobject]@{
                ComputerName = $cn
                WsmanOk      = $wsmanOk
                WsmanError   = $wsmanError
                TcpPort      = $tcpPort
                TcpPortOpen  = $tcpOpen
            }
        }
    }
}
