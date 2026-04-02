#requires -version 7.5

<#
.SYNOPSIS
Generates or updates README.md files across the repository using consistent templates and optional file indexing.

.DESCRIPTION
Generates README.md content for key repository directories and ensures formatting is consistent.
Content is inserted into a managed section bounded by markers so you can keep manual edits outside the generated block.

By default, this script:
- Discovers the repo root
- Ensures required READMEs exist for known directories (Azure, Terraform, WinMgmt, build/tools, etc.)
- Writes or updates only the managed block in each README
- Optionally indexes files within each directory and includes an "Indexed Files" section

Use -WhatIf to preview changes without writing.
Use -VerifyOnly in CI to fail if the generated content differs from committed READMEs.

.WHAT THIS DOES
- Creates README.md if missing
- Updates only the managed section between markers:
  <!-- BEGIN:AUTOGEN -->
  <!-- END:AUTOGEN -->
- Generates consistent structure and repo-aware descriptions
- Optionally indexes files in each directory and lists them in Markdown
- Supports -WhatIf / -Confirm via SupportsShouldProcess
- Supports -VerifyOnly mode for CI validation

.REQUIREMENTS
- PowerShell 7.5+
- Repo checked out locally (file system access)
- Write access to README paths (unless using -VerifyOnly)

.EXAMPLE
# Generate/refresh all READMEs (writes changes)
.\build\Generate-Readmes.ps1

.EXAMPLE
# Preview changes only (no writes)
.\build\Generate-Readmes.ps1 -WhatIf

.EXAMPLE
# Include file indexing (recommended)
.\build\Generate-Readmes.ps1 -IncludeIndex

.EXAMPLE
# Include indexing recursively, limit per directory
.\build\Generate-Readmes.ps1 -IncludeIndex -RecurseIndex -MaxIndexItems 200

.EXAMPLE
# Verify only (CI mode). Exits non-zero if changes would be made.
.\build\Generate-Readmes.ps1 -VerifyOnly -IncludeIndex

.NOTES
  .AUTHOR
  Richard Taylor (@slkrck)

  .DATE CREATED
  2026-02-02

  .VERSION
  0.0.0

  .LICENSE
  MIT License
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# region Constants

$AutogenBegin = '<!-- BEGIN:AUTOGEN -->'
$AutogenEnd   = '<!-- END:AUTOGEN -->'

# endregion Constants

# region Helper Functions

function Get-RepoRoot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$StartPath = (Get-Location).Path
    )

    $p = Resolve-Path -LiteralPath $StartPath
    $cur = $p.Path

    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $cur '.git')) { return $cur }
        $parent = Split-Path -Parent $cur
        if (-not $parent -or $parent -eq $cur) {
            throw "Could not locate repo root (.git) starting from '$StartPath'."
        }
        $cur = $parent
    }
}

function New-MarkdownLink {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$RelativePath
    )
    return "[$Text]($RelativePath)"
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To
    )

    $fromUri = [Uri]((Resolve-Path -LiteralPath $From).Path + [IO.Path]::DirectorySeparatorChar)
    $toUri   = [Uri]((Resolve-Path -LiteralPath $To).Path)

    $rel = $fromUri.MakeRelativeUri($toUri).ToString()
    # Normalize to GitHub-friendly forward slashes
    return ($rel -replace '%20',' ' -replace '\\','/')
}

function Get-DirectoryIndexMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DirectoryPath,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [int]$MaxItems = 150
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath)) { return $null }

    $items = Get-ChildItem -LiteralPath $DirectoryPath -Force -File -ErrorAction SilentlyContinue `
        -Recurse:$Recurse |
        Where-Object {
            # ignore typical noise
            $_.FullName -notmatch '(\\|/)\.git(\\|/)' -and
            $_.FullName -notmatch '(\\|/)node_modules(\\|/)' -and
            $_.FullName -notmatch '(\\|/)bin(\\|/)' -and
            $_.FullName -notmatch '(\\|/)obj(\\|/)' -and
            $_.FullName -notmatch '(\\|/)out(\\|/)' -and
            $_.FullName -notmatch '(\\|/)\.terraform(\\|/)'
        } |
        Sort-Object FullName

    if (-not $items) { return $null }

    if ($items.Count -gt $MaxItems) {
        $items = $items | Select-Object -First $MaxItems
        $truncatedNote = $true
    }
    else {
        $truncatedNote = $false
    }

    # Group by extension, but keep common “types” first
    $extOrder = @('.ps1','.psm1','.psd1','.tf','.md','.yml','.yaml','.json','.txt','.html')
    $groups = $items | Group-Object Extension | Sort-Object {
        $idx = $extOrder.IndexOf($_.Name)
        if ($idx -lt 0) { 999 } else { $idx }
    }, Name

    $md = New-Object System.Collections.Generic.List[string]
    $md.Add("### Indexed Files")
    $md.Add("")
    $md.Add("This section is generated. It lists files found in this directory" + ($(if($Recurse){ " (recursive)" } else { "" })) + ".")
    if ($truncatedNote) {
        $md.Add("")
        $md.Add("> Note: Output truncated to the first $MaxItems files.")
    }
    $md.Add("")

    foreach ($g in $groups) {
        $ext = if ([string]::IsNullOrWhiteSpace($g.Name)) { '(no extension)' } else { $g.Name }
        $md.Add("#### $ext")
        $md.Add("")
        foreach ($f in $g.Group) {
            $name = $f.Name
            $md.Add("- `$name`")
        }
        $md.Add("")
    }

    return ($md -join "`n").TrimEnd()
}

function Get-OrCreateReadmeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ReadmePath,
        [Parameter()][string]$TitleLine
    )

    if (Test-Path -LiteralPath $ReadmePath) {
        return Get-Content -LiteralPath $ReadmePath -Raw
    }

    # Minimal initial README shell with markers and a safe title
    $title = if ($TitleLine) { $TitleLine } else { '# README' }
    return @"
$title

$AutogenBegin
$AutogenEnd
"@
}

function Upsert-AutogenBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExistingText,
        [Parameter(Mandatory)][string]$GeneratedBlock
    )

    $begin = [regex]::Escape($AutogenBegin)
    $end   = [regex]::Escape($AutogenEnd)

    # If markers exist, replace contents between them.
    if ($ExistingText -match "(?s)$begin.*?$end") {
        $replacement = '$1' + "`n$GeneratedBlock`n" + '$2'
        return [regex]::Replace(
            $ExistingText,
            "(?s)($begin).*?($end)",
            $replacement
        )
    }

    # Otherwise, append markers + block at end
    $trim = $ExistingText.TrimEnd()
    return @"
$trim

$AutogenBegin
$GeneratedBlock
$AutogenEnd
"@
}

function New-ReadmeBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Heading,
        [Parameter(Mandatory)][string]$Description,
        [Parameter()][string[]]$Bullets,
        [Parameter()][string]$IndexMarkdown,
        [Parameter()][string]$RelativeBackLink
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("## $Heading")
    $lines.Add("")
    $lines.Add($Description.Trim())
    $lines.Add("")

    if ($Bullets -and $Bullets.Count -gt 0) {
        foreach ($b in $Bullets) { $lines.Add("- $b") }
        $lines.Add("")
    }

    if ($RelativeBackLink) {
        $lines.Add("_Back to " + (New-MarkdownLink -Text "Repository Root" -RelativePath $RelativeBackLink) + "._")
        $lines.Add("")
    }

    if ($IndexMarkdown) {
        $lines.Add($IndexMarkdown.Trim())
        $lines.Add("")
    }

    return ($lines -join "`n").TrimEnd()
}

# endregion Helper Functions

# region Main

function Invoke-ReadmeGeneration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$RepoRoot,

        [Parameter()]
        [switch]$IncludeIndex,

        [Parameter()]
        [switch]$RecurseIndex,

        [Parameter()]
        [ValidateRange(10,2000)]
        [int]$MaxIndexItems = 150,

        [Parameter()]
        [switch]$VerifyOnly
    )

    $root = if ($RepoRoot) { (Resolve-Path -LiteralPath $RepoRoot).Path } else { Get-RepoRoot }

    # Define READMEs we manage (path => template metadata)
    $targets = @(
        @{
            Path        = 'README.md'
            Title       = '# Infrastructure Automation Repository'
            Heading     = 'Repository Overview'
            Description = 'This repository contains reusable automation, tooling, and reference implementations for infrastructure, cloud, and systems management workflows.'
            Bullets     = @(
                '**Azure/** – Azure scripts, snippets, and tests',
                '**Terraform/** – Terraform modules and examples',
                '**WinMgmt/** – Windows management scripts, modules, and tests',
                '**build/** – repo build/test/docs tooling',
                '**tests/** – repo-wide enforcement and style tests'
            )
            IndexDir    = $null
        },
        @{
            Path        = 'Azure/README.md'
            Title       = '# Azure Automation'
            Heading     = 'Azure Automation'
            Description = 'Azure-focused automation, scripts, snippets, and tests.'
            Bullets     = @('SCRIPTS/ – executable scripts','SNIPS/ – reusable building blocks','PesterTests/ – tests for Azure tooling')
            IndexDir    = 'Azure'
        },
        @{
            Path        = 'Azure/SNIPS/README.md'
            Title       = '# Azure Snippets (SNIPS)'
            Heading     = 'Azure Snippets'
            Description = 'Reusable Azure snippets intended to be imported, dot-sourced, or embedded into higher-level scripts and modules.'
            Bullets     = @('functions/ – reusable PowerShell functions','modules/ – module fragments and scaffolding')
            IndexDir    = 'Azure/SNIPS'
        },
        @{
            Path        = 'Azure/SNIPS/functions/README.md'
            Title       = '# Azure SNIPS – Functions'
            Heading     = 'Azure Functions'
            Description = 'Standalone reusable PowerShell functions related to Azure automation.'
            Bullets     = @('Functions should be side-effect free on import','Prefer comment-based help and consistent parameter patterns')
            IndexDir    = 'Azure/SNIPS/functions'
        },
        @{
            Path        = 'Azure/SNIPS/modules/README.md'
            Title       = '# Azure SNIPS – Modules'
            Heading     = 'Azure Modules'
            Description = 'Module-oriented Azure components and scaffolding.'
            Bullets     = @('Prototyping and internal reuse','Promote mature modules to a dedicated module directory when ready')
            IndexDir    = 'Azure/SNIPS/modules'
        },
        @{
            Path        = 'Terraform/README.md'
            Title       = '# Terraform Automation'
            Heading     = 'Terraform Automation'
            Description = 'Terraform modules and supporting documentation.'
            Bullets     = @('Modules/ – reusable Terraform modules')
            IndexDir    = 'Terraform'
        },
        @{
            Path        = 'Terraform/Modules/README.md'
            Title       = '# Terraform Modules'
            Heading     = 'Terraform Modules'
            Description = 'Reusable Terraform modules designed for composition into larger deployments.'
            Bullets     = @('Each module should document inputs, outputs, and usage')
            IndexDir    = 'Terraform/Modules'
        },
        @{
            Path        = 'Terraform/Modules/Examples/README.md'
            Title       = '# Terraform Module Examples'
            Heading     = 'Examples'
            Description = 'Example implementations demonstrating module usage.'
            Bullets     = @('Reference configurations','Validation and smoke tests','Starting points for deployments')
            IndexDir    = 'Terraform/Modules/Examples'
        },
        @{
            Path        = 'WinMgmt/README.md'
            Title       = '# Windows Management (WinMgmt)'
            Heading     = 'Windows Management'
            Description = 'PowerShell scripts, modules, snippets, and tests for Windows system management and automation.'
            Bullets     = @('MODULES/ – PowerShell modules','SCRIPTS/ – executable tools','SNIPS/ – reusable helpers','PesterTests/ – tests')
            IndexDir    = 'WinMgmt'
        },
        @{
            Path        = 'WinMgmt/SCRIPTS/README.md'
            Title       = '# WinMgmt Scripts'
            Heading     = 'Scripts'
            Description = 'Executable PowerShell scripts for Windows management tasks.'
            Bullets     = @('Designed for operators','Supports local and remote execution','Leverages SNIPS and modules where appropriate')
            IndexDir    = 'WinMgmt/SCRIPTS'
        },
        @{
            Path        = 'WinMgmt/SNIPS/README.md'
            Title       = '# WinMgmt Snippets (SNIPS)'
            Heading     = 'Snippets'
            Description = 'Reusable Windows management snippets intended to be imported or dot-sourced.'
            Bullets     = @('functions/ – reusable functions','modules/ – module fragments and scaffolding')
            IndexDir    = 'WinMgmt/SNIPS'
        },
        @{
            Path        = 'WinMgmt/SNIPS/functions/README.md'
            Title       = '# WinMgmt SNIPS – Functions'
            Heading     = 'Functions'
            Description = 'Reusable functions for connectivity, session lifecycle, and WinRM/CIM interactions.'
            Bullets     = @('Keep functions focused and composable','Prefer safe session cleanup helpers')
            IndexDir    = 'WinMgmt/SNIPS/functions'
        },
        @{
            Path        = 'WinMgmt/SNIPS/modules/README.md'
            Title       = '# WinMgmt SNIPS – Modules'
            Heading     = 'Modules'
            Description = 'Module components and internal tooling used to enforce standards and enable reuse.'
            Bullets     = @('RepoBootstrap lives here as internal scaffolding','Modules may include build and tests')
            IndexDir    = 'WinMgmt/SNIPS/modules'
        },
        @{
            Path        = 'build/tools/README.md'
            Title       = '# Build Tools'
            Heading     = 'Build Tools'
            Description = 'Reusable helper scripts that support repository automation and documentation.'
            Bullets     = @('DocTools.ps1 – versioning/document tooling','Show-RepoTree.ps1 – repo-aware tree output','TreeTool.ps1 – generic tree helpers')
            IndexDir    = 'build/tools'
        }
    )

    $anyChanges = $false
    $diffSummary = New-Object System.Collections.Generic.List[string]

    foreach ($t in $targets) {
        $readmeFull = Join-Path $root $t.Path
        $readmeDir  = Split-Path -Parent $readmeFull

        if (-not (Test-Path -LiteralPath $readmeDir)) {
            # Directory doesn't exist; skip quietly (keeps generator resilient)
            continue
        }

        $existing = Get-OrCreateReadmeText -ReadmePath $readmeFull -TitleLine $t.Title

        $backLink = $null
        if ($t.Path -ne 'README.md') {
            $backLink = Get-RelativePath -From $readmeDir -To (Join-Path $root 'README.md')
        }

        $indexMd = $null
        if ($IncludeIndex -and $t.IndexDir) {
            $indexPath = Join-Path $root $t.IndexDir
            $indexMd = Get-DirectoryIndexMarkdown -DirectoryPath $indexPath -Recurse:$RecurseIndex -MaxItems $MaxIndexItems
        }

        $block = New-ReadmeBlock -Heading $t.Heading -Description $t.Description -Bullets $t.Bullets -IndexMarkdown $indexMd -RelativeBackLink $backLink
        $updated = Upsert-AutogenBlock -ExistingText $existing -GeneratedBlock $block

        if ($updated -ne $existing) {
            $anyChanges = $true
            $diffSummary.Add("Would update: $($t.Path)")

            if (-not $VerifyOnly) {
                if ($PSCmdlet.ShouldProcess($t.Path, "Write README managed block")) {
                    # Ensure README exists and write UTF-8 without BOM for GitHub
                    New-Item -ItemType Directory -Path $readmeDir -Force | Out-Null
                    Set-Content -LiteralPath $readmeFull -Value $updated -Encoding utf8
                }
            }
        }
    }

    if ($VerifyOnly) {
        if ($anyChanges) {
            $msg = "README generation verification failed. Differences detected:`n - " + ($diffSummary -join "`n - ")
            throw $msg
        }
        return
    }

    if ($anyChanges) {
        Write-Host "README generation complete. Updated managed blocks where needed."
    }
    else {
        Write-Host "README generation complete. No changes required."
    }
}

# endregion Main

# Entry point (script execution)
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$RepoRoot,

    [Parameter()]
    [switch]$IncludeIndex,

    [Parameter()]
    [switch]$RecurseIndex,

    [Parameter()]
    [ValidateRange(10,2000)]
    [int]$MaxIndexItems = 150,

    [Parameter()]
    [switch]$VerifyOnly
)

Invoke-ReadmeGeneration -RepoRoot $RepoRoot -IncludeIndex:$IncludeIndex -RecurseIndex:$RecurseIndex -MaxIndexItems $MaxIndexItems -VerifyOnly:$VerifyOnly
