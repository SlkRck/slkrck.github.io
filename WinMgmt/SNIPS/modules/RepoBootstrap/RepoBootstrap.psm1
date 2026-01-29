<#
    .SYNOPSIS
        Ensures an existing GitHub repo is cloned locally, creates a standardized folder structure beneath it, seeds per-folder README.md files, and overwrites the repo-root README.md with a structured table of contents.

    .DESCRIPTION
        This command bootstraps (or normalizes) a working copy of an existing GitHub repository using GitHub CLI and Git.

        Core behaviors:
          - Validates required tooling is available (gh, git).
          - Resolves the currently-authenticated GitHub user via `gh api user`.
          - Clones the repo locally to a chosen base path if it does not already exist.
          - Creates a predefined folder layout under the repo root.
          - Creates a README.md in each created folder if missing (does not overwrite existing folder READMEs).
          - Overwrites the repo-root README.md with a structured table of contents and conventions section (always overwrites).
          - Stages, commits, and pushes changes only when changes are detected.

    .PARAMETER RepoName
        Repository name (without owner). Defaults to "slkrck.github.io".

    .PARAMETER BasePath
        Local parent directory where the repo should live (clone target). Defaults to "$HOME\src".

    .PARAMETER CommitMsg
        Commit message used when changes are detected and committed.

    .PARAMETER NoPush
        If specified, performs all local changes and commits, but does not push to origin.

    .PARAMETER Owner
        DEV ONLY.
        Overrides GitHub owner resolution. Intended for testing, CI, or offline runs.

    .PARAMETER RepoPathOverride
        DEV ONLY.
        Operate on an existing local repository path instead of cloning.
        Intended for Pester tests and sandbox execution.


    .EXAMPLE
        Invoke-RepoStructureBootstrap

    .EXAMPLE
        Invoke-RepoStructureBootstrap -BasePath "C:\src" -CommitMsg "Initialize structure"

    .EXAMPLE
        Invoke-RepoStructureBootstrap -NoPush

    .NOTES
        Prerequisites:
          - GitHub CLI (`gh`) installed and authenticated (run: gh auth login)
          - Git installed and available on PATH
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Command {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function New-FolderWithReadme {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, "Create directory")) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }

    $readme = Join-Path $Path "README.md"
    if (-not (Test-Path -LiteralPath $readme)) {
        $folderName = Split-Path -Leaf $Path
        $content = @"
# $folderName

> Describe what belongs in this folder.
"@
        if ($PSCmdlet.ShouldProcess($readme, "Create README.md (seed)")) {
            $content | Set-Content -LiteralPath $readme -Encoding UTF8
        }
    }
}

function Write-RootReadmeToc {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepoName
    )

    $rootReadme = Join-Path $RepoPath "README.md"

    $content = @"
# $RepoName

This repository contains organized snippets, scripts, and Terraform modules.

## Table of contents

- [WinMgmt](./WinMgmt/)
  - [SNIPS](./WinMgmt/SNIPS/)
    - [modules](./WinMgmt/SNIPS/modules/)
    - [functions](./WinMgmt/SNIPS/functions/)
  - [SCRIPTS](./WinMgmt/SCRIPTS/)

- [Azure](./Azure/)
  - [SNIPS](./Azure/SNIPS/)
    - [modules](./Azure/SNIPS/modules/)
    - [functions](./Azure/SNIPS/functions/)

- [Terraform](./Terraform/)
  - [Modules](./Terraform/Modules/)
    - [Examples](./Terraform/Modules/Examples/)

## Conventions

- Keep reusable code in `SNIPS/`.
- Put publishable PowerShell modules under `SNIPS/modules/`.
- Put single-purpose helper functions under `SNIPS/functions/`.
- Put runnable scripts in `SCRIPTS/`.
- Terraform modules live under `Terraform/Modules/`.

"@

    if ($PSCmdlet.ShouldProcess($rootReadme, "Overwrite root README.md with TOC")) {
        $content | Set-Content -LiteralPath $rootReadme -Encoding UTF8
    }
}


function Invoke-RepoStructureBootstrap {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RepoName = "slkrck.github.io",

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$BasePath = (Join-Path $HOME "src"),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CommitMsg = "Add baseline folder structure + README table of contents",

        [Parameter()]
        [switch]$NoPush,
    

    # DEV-ONLY OVERRIDES
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Owner,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RepoPathOverride
)

    Assert-Command gh
    Assert-Command git

    if (-not (Test-Path -LiteralPath $BasePath)) {
        if ($PSCmdlet.ShouldProcess($BasePath, "Create base path")) {
            New-Item -ItemType Directory -Path $BasePath -Force | Out-Null
        }
    }

    Push-Location $BasePath
    try {
        if ($Owner) {
    Write-Verbose "Using supplied Owner override: $Owner"
    $owner = $Owner
}
    else {
        $owner = (gh api user --jq .login).Trim()
        if (-not $owner) {
            throw "Unable to determine GitHub username. Run: gh auth status or supply -Owner."
        }
    }


       $fullName = "$owner/$RepoName"

        if ($RepoPathOverride) {
            Write-Verbose "Using RepoPathOverride: $RepoPathOverride"
            $repoPath = $RepoPathOverride
        }
        else {
            $repoPath = Join-Path $BasePath $RepoName
        }


        if (-not $RepoPathOverride) {
            if (-not (Test-Path -LiteralPath $repoPath)) {
                if ($PSCmdlet.ShouldProcess($repoPath, "Clone repo $fullName")) {
                    gh repo clone $fullName
                }
            }
        }
        else {
            if (-not (Test-Path -LiteralPath $repoPath)) {
                throw "RepoPathOverride '$repoPath' does not exist."
            }
        }


        Set-Location $repoPath

        if (-not (Test-Path -LiteralPath (Join-Path $repoPath ".git"))) {
            throw "Path '$repoPath' does not appear to be a git repository."
        }

        $foldersToCreate = @(
            "WinMgmt",
            "WinMgmt\SNIPS",
            "WinMgmt\SNIPS\modules",
            "WinMgmt\SNIPS\functions",
            "WinMgmt\SCRIPTS",

            "Azure",
            "Azure\SNIPS",
            "Azure\SNIPS\modules",
            "Azure\SNIPS\functions",

            "Terraform",
            "Terraform\Modules",
            "Terraform\Modules\Examples"
        )

        foreach ($rel in $foldersToCreate) {
            New-FolderWithReadme -Path (Join-Path $repoPath $rel) -WhatIf:$WhatIfPreference
        }

        Write-RootReadmeToc -RepoPath $repoPath -RepoName $RepoName -WhatIf:$WhatIfPreference

        if ($PSCmdlet.ShouldProcess($repoPath, "git add -A")) {
            git add -A
        }

        $status = (git status --porcelain)
        if ($status) {
            if ($PSCmdlet.ShouldProcess($repoPath, "git commit")) {
                git commit -m $CommitMsg
            }

            if (-not $NoPush) {
                if ($PSCmdlet.ShouldProcess($repoPath, "git push")) {
                    git push
                }
                Write-Host "Pushed changes to $fullName"
            } else {
                Write-Host "Committed changes locally (NoPush specified). Repo: $fullName"
            }
        } else {
            Write-Host "No changes to commit; structure/README already up-to-date."
        }

        [pscustomobject]@{
            Repo       = $fullName
            RepoPath   = $repoPath
            BasePath   = $BasePath
            Pushed     = (-not $NoPush) -and [bool]$status
            HadChanges = [bool]$status
        }
    }
    finally {
        Pop-Location
    }
}

Export-ModuleMember -Function Invoke-RepoStructureBootstrap
