#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$moduleRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) # up from build\
$psd1 = Join-Path $moduleRoot 'RepoBootstrap.psd1'

# Ensure Pester available
if (-not (Get-Module -ListAvailable -Name Pester)) {
    throw "Pester not found. Install-Module Pester -Scope CurrentUser"
}

# Run tests
Invoke-Pester -Path (Join-Path $moduleRoot 'tests') -CI

# Determine version from manifest
$manifest = Import-PowerShellDataFile -Path $psd1
$version = $manifest.ModuleVersion

# Build output
$outRoot = Join-Path $moduleRoot 'out'
if (-not (Test-Path $outRoot)) { New-Item -ItemType Directory -Path $outRoot | Out-Null }

$artifactName = "RepoBootstrap-$version.zip"
$artifactPath = Join-Path $outRoot $artifactName

# Zip module content (excluding out/)
if (Test-Path $artifactPath) { Remove-Item $artifactPath -Force }
$items = Get-ChildItem -Path $moduleRoot -Force |
    Where-Object { $_.Name -notin @('out') }

Compress-Archive -Path $items.FullName -DestinationPath $artifactPath -Force

Write-Host "Built artifact: $artifactPath"
