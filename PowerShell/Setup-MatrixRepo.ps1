<#
.SYNOPSIS
    One-time setup: creates a GitHub repository and initializes git tracking
    for WorkPriorityMatrix. Run this once from any PowerShell terminal.

.REQUIREMENTS
    - git  (https://git-scm.com)
    - gh   (https://cli.github.com  — run: winget install GitHub.cli)
    - gh auth login  (run once to authenticate)

.USAGE
    .\Setup-MatrixRepo.ps1 [-RepoName 'WorkPriorityMatrix'] [-LocalPath 'C:\Projects\WorkPriorityMatrix'] [-Private]
#>

[CmdletBinding()]
param(
    [string]$RepoName  = 'WorkPriorityMatrix',
    [string]$LocalPath = "$env:USERPROFILE\Documents\WorkPriorityMatrix",
    [switch]$Private
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step ([string]$Msg) {
    Write-Host "`n==> $Msg" -ForegroundColor Cyan
}

# ── Verify prerequisites ──────────────────────────────────────────
Write-Step 'Checking prerequisites'

foreach ($cmd in @('git','gh')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "$cmd not found. Install it and re-run.  (winget install GitHub.cli)"
    }
}

$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not authenticated with GitHub. Run:  gh auth login"
}
Write-Host "  git and gh found. GitHub auth OK." -ForegroundColor Green

# ── Create local folder ───────────────────────────────────────────
Write-Step "Creating local project folder: $LocalPath"
New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null

# ── Copy the script into the repo folder ─────────────────────────
Write-Step 'Copying WorkPriorityMatrix_v2.ps1'
$scriptSrc = Join-Path $PSScriptRoot 'WorkPriorityMatrix_v2.ps1'
if (-not (Test-Path $scriptSrc)) {
    # Fallback: look in same folder as this setup script
    $scriptSrc = Join-Path (Split-Path $MyInvocation.MyCommand.Path) 'WorkPriorityMatrix_v2.ps1'
}
if (-not (Test-Path $scriptSrc)) {
    Write-Error "Cannot find WorkPriorityMatrix_v2.ps1. Place it in the same folder as this setup script."
}
Copy-Item $scriptSrc $LocalPath -Force
Write-Host "  Copied to $LocalPath" -ForegroundColor Green

# ── Write a .gitignore ────────────────────────────────────────────
Write-Step 'Writing .gitignore'
@'
# Saved matrix data files (JSON) — commit these if you want history of your tasks
# *.json

# Windows junk
Thumbs.db
desktop.ini

# PowerShell session files
*.psess
'@ | Set-Content (Join-Path $LocalPath '.gitignore') -Encoding UTF8

# ── Write a README ────────────────────────────────────────────────
Write-Step 'Writing README.md'
@"
# Work Priority Matrix

A PowerShell Windows Forms GUI for daily task prioritization using the Covey urgent/important framework.

## Quadrant assignments

| Urgency | Importance | Quadrant | Level |
|---------|------------|----------|-------|
| Today   | Important  | Q1 Do Now | H |
| Today   | Somewhat   | Q1 Do Now | M |
| Today   | Not        | Q4 Eliminate | H |
| Soon    | Important  | Q2 Schedule | H |
| Soon    | Somewhat   | Q2 Schedule | M |
| Soon    | Not        | Q3 Delegate | M |
| Later   | Important  | Q2 Schedule | L |
| Later   | Somewhat   | Q3 Delegate | H |
| Later   | Not        | Q3 Delegate | L |

## Features (v2)

- Object-based task model with GUID IDs
- Save / Load JSON  (Ctrl+S / Ctrl+O)
- Export to CSV
- Edit task by double-clicking
- Drag-and-drop reordering within and between quadrants
- Keyboard shortcuts: Esc, Delete, Ctrl+S/O/N
- Status bar feedback

## Running

``````powershell
.\WorkPriorityMatrix_v2.ps1
``````

## Auto-commit watcher

Run ``Watch-MatrixChanges.ps1`` in a background terminal to automatically commit
every time you save the script or a JSON matrix file.

## Version history

| Version | Notes |
|---------|-------|
| 1.0–1.5.3 | Initial working builds, string-based storage |
| 2.0.0 | Object model, save/load, edit task, keyboard shortcuts |
"@ | Set-Content (Join-Path $LocalPath 'README.md') -Encoding UTF8

# ── Git init and first commit ─────────────────────────────────────
Write-Step 'Initializing git repository'
Push-Location $LocalPath

git init
git add .
git commit -m 'feat: initial commit — WorkPriorityMatrix v2.0'

# ── Create GitHub repo and push ───────────────────────────────────
Write-Step "Creating GitHub repository '$RepoName'"
$vis = if ($Private) { '--private' } else { '--public' }
gh repo create $RepoName $vis --source . --remote origin --push

$repoUrl = gh repo view $RepoName --json url -q '.url'
Write-Host "`n  Repository created: $repoUrl" -ForegroundColor Green

Pop-Location

Write-Host @"

Done!  Your repository is live at:
  $repoUrl

Next steps:
  1. Run Watch-MatrixChanges.ps1 in a background terminal to auto-commit on save.
  2. Or commit manually:  cd '$LocalPath' ; git add . ; git commit -m 'your message' ; git push

"@ -ForegroundColor Yellow
