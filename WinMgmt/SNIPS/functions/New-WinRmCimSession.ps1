# FILE: WinMgmt\SNIPS\functions\New-WinRmCimSession.ps1
<#
.SYNOPSIS
Creates a CIM session over WinRM (WSMan) with standardized options and timeouts.

.DESCRIPTION
New-WinRmCimSession wraps New-CimSession for WinRM usage and standardizes:
- Authentication
- Optional credentials
- WSMan operation timeout (OperationTimeoutSec)
- Error handling (-ErrorAction Stop)

This is designed as a reusable building block for WinMgmt scripts and functions.

.WHAT THIS DOES
- Builds a New-CimSessionOption for WSMan
- Creates a CIM session with consistent defaults
- Throws terminating errors on failure

.REQUIREMENTS
- PowerShell 7+ or Windows PowerShell 5.1
- WinRM enabled and accessible on target

.PARAMETER ComputerName
Target computer name.

.PARAMETER Credential
Optional credential.

.PARAMETER Authentication
Authentication mechanism. Defaults to Negotiate.

.PARAMETER WsmanOperationTimeoutSeconds
WSMan operation timeout in seconds.

.EXAMPLE
Create a CIM session with defaults.
$session = New-WinRmCimSession -ComputerName 'SERVER01'

.EXAMPLE
Create a CIM session with explicit credential and increased timeout.
$cred = Get-Credential
$session = New-WinRmCimSession -ComputerName 'SERVER01' -Credential $cred -WsmanOperationTimeoutSeconds 60

.OUTPUTS
Microsoft.Management.Infrastructure.CimSession

.NOTES
- Always uses -ErrorAction Stop so callers can reliably catch failures.

#>
function New-WinRmCimSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [ValidateSet('Default','Basic','Negotiate','Kerberos','NtlmDomain','Digest','CredSsp')]
        [string]$Authentication = 'Negotiate',

        [Parameter()]
        [ValidateRange(5,600)]
        [int]$WsmanOperationTimeoutSeconds = 30
    )

    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        throw "ComputerName cannot be empty or whitespace."
    }

    $sessionOption = New-CimSessionOption -Protocol Wsman -OperationTimeoutSec $WsmanOperationTimeoutSeconds

    $params = @{
        ComputerName   = $ComputerName
        Authentication = $Authentication
        SessionOption  = $sessionOption
        ErrorAction    = 'Stop'
    }

    if ($Credential) {
        $params.Credential = $Credential
    }

    $session = New-CimSession @params
    if (-not $session) {
        throw "New-CimSession returned null for [$ComputerName]."
    }

    $session
}
