# FILE: WinMgmt\Modules\WinMgmt\WinMgmt.psm1
<#
.SYNOPSIS
WinMgmt PowerShell module.

.DESCRIPTION
Loads WinMgmt functions from WinMgmt\SNIPS\functions (single source of truth) and exports selected functions
via the module manifest.

.NOTES
Loads functions in a dependency-friendly order.
#>

Set-StrictMode -Version Latest

$moduleRoot  = $PSScriptRoot                          # ...\WinMgmt\Modules\WinMgmt
$winMgmtRoot = Resolve-Path (Join-Path $moduleRoot '..\..')  # ...\WinMgmt
$functionRoot = Join-Path $winMgmtRoot 'SNIPS\functions'

if (-not (Test-Path $functionRoot)) {
    throw "WinMgmt function root not found: $functionRoot"
}

# Load in dependency-friendly order (explicit list)
$filesToLoad = @(
    'Test-HostReachable.ps1',
    'Test-WinRmReady.ps1',
    'Remove-SafeCimSession.ps1',
    'New-WinRmCimSession.ps1',
    'Assert-RunningAsAdmin.ps1',
    'Get-RemoteNetworkAdapterInfo.ps1'
)

foreach ($file in $filesToLoad) {
    $path = Join-Path $functionRoot $file
    if (-not (Test-Path $path)) {
        throw "Required function file missing: $path"
    }
    . $path
}
