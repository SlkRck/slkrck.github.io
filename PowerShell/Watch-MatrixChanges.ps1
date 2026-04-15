<#
.SYNOPSIS
    Watches the WorkPriorityMatrix project folder and auto-commits to git
    every time the PowerShell script or a JSON matrix file is saved.

.USAGE
    # Run in a separate terminal — leave it running while you work
    .\Watch-MatrixChanges.ps1 [-Path 'CC:\Users\slick\OneDrive\.git\slkrck.github.io\PowerShell'] [-IntervalSeconds 10]

.HOW IT WORKS
    Every $IntervalSeconds the watcher checks whether any tracked file has been
    modified since the last check.  If so, it stages all changes and commits
    with an automatic message including the timestamp and a list of changed files.
    It then pushes to origin/main.

    You can also commit manually at any time — the watcher will skip cleanly
    if there is nothing new to commit.
#>

[CmdletBinding()]
param(
    [string]$Path            = "C:\Users\slick\OneDrive\.git\slkrck.github.io\PowerShell",
    [int]   $IntervalSeconds = 10,
    [switch]$NoPush          # set this flag to commit locally only, no push
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if (-not (Test-Path $Path)) {
    Write-Error "Project folder not found: $Path`nRun Setup-MatrixRepo.ps1 first."
    exit 1
}

Push-Location $Path

function Write-Watch ([string]$Msg, [string]$Color = 'Gray') {
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))]  $Msg" -ForegroundColor $Color
}

Write-Watch "Watching '$Path' every ${IntervalSeconds}s.  Press Ctrl+C to stop." 'Cyan'
Write-Watch "Remote push: $(if ($NoPush) {'disabled'} else {'enabled (origin/main)'})" 'Cyan'
Write-Host ''

# Track the last time we looked
$script:LastCheck = [datetime]::MinValue

while ($true) {
    Start-Sleep -Seconds $IntervalSeconds

    try {
        # Ask git if there is anything uncommitted
        $status = git status --porcelain 2>&1
        if (-not $status) {
            # Nothing to do
            continue
        }

        # Build a short summary of what changed
        $changed = $status -split "`n" |
            Where-Object { $_.Trim() } |
            ForEach-Object { $_.Trim().Substring(3) }   # strip the XY status codes

        $summary = $changed -join ', '
        if ($summary.Length -gt 80) { $summary = $summary.Substring(0,77) + '...' }

        $msg = "auto: save $([datetime]::Now.ToString('yyyy-MM-dd HH:mm'))  [$summary]"

        git add --all
        $commitOut = git commit -m $msg 2>&1
        Write-Watch "Committed: $msg" 'Green'

        if (-not $NoPush) {
            $pushOut = git push origin HEAD 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Watch 'Pushed to origin.' 'Green'
            } else {
                Write-Watch "Push failed (will retry next interval): $pushOut" 'Yellow'
            }
        }
    }
    catch {
        Write-Watch "Error during commit cycle: $_" 'Red'
    }
}

Pop-Location
