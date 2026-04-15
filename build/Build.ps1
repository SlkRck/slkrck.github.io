#requires -version 7.5
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'tools\DocTools.ps1')

# --- Paths (your structure) ---
$scriptPath = Join-Path $repoRoot 'WinMgmt\SCRIPTS\Show-SystemStatus.ps1'
$outDir     = Join-Path $repoRoot 'out'

# Optional module manifest update if/when you convert this to a module
$moduleManifestPath = Join-Path $repoRoot 'WinMgmt\WinMgmt.psd1'  # adjust if present

# --- Derive version from git tags ---
$version = Get-GitVersion -RepoRoot $repoRoot -TagPrefix 'v'
Write-Host "Build Version: $version"

# --- Update .VERSION in the script comment-help blocks ---
# (This will update the first .VERSION occurrence it finds. If you want ALL help blocks updated,
# call it multiple times with an "update all occurrences" variant; see note below.)
Update-CommentHelpVersionBlock -Path $scriptPath -Version $version -WhatIf:$false

# --- Run Pester (optional, only if tests exist) ---
$testsPath = Join-Path $repoRoot 'tests'
if (Test-Path $testsPath) {
    $pester = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
    if (-not $pester) {
        throw "Pester is not installed. Install-Module Pester -Scope CurrentUser"
    }
    Invoke-Pester -Path $testsPath -CI
}

# --- Package artifact ---
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$artifactName = "Show-SystemStatus-$version.zip"
$artifactPath = Join-Path $outDir $artifactName

if (Test-Path $artifactPath) { Remove-Item -LiteralPath $artifactPath -Force }

Compress-Archive -Path $scriptPath -DestinationPath $artifactPath -Force

Write-Host "Created: $artifactPath"
