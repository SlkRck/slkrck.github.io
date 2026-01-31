<#
.SYNOPSIS
Runs repo Pester tests using Pester 5+ (forces correct module) with configurable verbosity.

.DESCRIPTION
Ensures legacy Pester (3.x/4.x) is not used. Imports Pester 5+ and executes Invoke-Pester
using New-PesterConfiguration for consistent behavior across machines and CI.

.EXAMPLES
```powershell
.\build\Invoke-RepoPester.ps1
.\build\Invoke-RepoPester.ps1 -Path .\tests\style -Verbosity Detailed
.\build\Invoke-RepoPester.ps1 -CI

#>

[CmdletBinding()]
param(
[Parameter()]
[string[]]$Path = @('.\tests'),
[Parameter()]
[ValidateSet('None','Normal','Detailed','Diagnostic')]
[string]$Verbosity = 'Detailed',

[Parameter()]
[switch]$CI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.0.0 -Force

$config = New-PesterConfiguration
$config.Run.Path = $Path

if ($CI) {
$config.Run.PassThru = $true | Out-Null
$config.Output.Verbosity = 'Normal'
} else {
$config.Output.Verbosity = $Verbosity
}

Invoke-Pester -Configuration $config


