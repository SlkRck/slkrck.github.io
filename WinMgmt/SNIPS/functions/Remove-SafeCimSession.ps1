# FILE: WinMgmt\SNIPS\functions\Remove-SafeCimSession.ps1
<#
.SYNOPSIS
Safely removes a CIM session (idempotent, null-safe).

.DESCRIPTION
Remove-SafeCimSession is a defensive wrapper around Remove-CimSession that accepts null
and silently handles failures. This prevents cleanup code from masking the real error.

.WHAT THIS DOES
- Checks for null input
- Attempts Remove-CimSession
- Suppresses cleanup exceptions

.REQUIREMENTS
- PowerShell 7+ or Windows PowerShell 5.1

.PARAMETER CimSession
A CIM session object (or null).

.EXAMPLE
Remove session safely.
Remove-SafeCimSession -CimSession $session

.OUTPUTS
None

.NOTES
- Intended for use in finally blocks.

#>
function Remove-SafeCimSession {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        $CimSession
    )

    process {
        if (-not $CimSession) { return }

        try {
            Remove-CimSession -CimSession $CimSession -ErrorAction SilentlyContinue
        }
        catch {
            # Intentionally suppress cleanup errors
        }
    }
}
