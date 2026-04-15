# FILE: WinMgmt\SNIPS\functions\Assert-RunningAsAdmin.ps1
<#
.SYNOPSIS
Asserts that the current PowerShell session is running elevated.

.DESCRIPTION
Assert-RunningAsAdmin is a small preflight helper that throws a terminating error
if the current process is not running with administrative privileges.

This is useful for scripts that require elevation (e.g., network resets, service config).

.WHAT THIS DOES
- Checks admin status
- Throws if not elevated

.REQUIREMENTS
- Windows (for elevation semantics)

.EXAMPLE
Fail fast if not elevated.
Assert-RunningAsAdmin

.OUTPUTS
None

.NOTES
- Uses a helper function Test-IsAdministrator to support mocking in Pester.

#>
function Test-IsAdministrator {
    [CmdletBinding()]
    param()

    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Assert-RunningAsAdmin {
    [CmdletBinding()]
    param()

    if (-not (Test-IsAdministrator)) {
        throw "This operation requires an elevated PowerShell session (Run as Administrator)."
    }
}
