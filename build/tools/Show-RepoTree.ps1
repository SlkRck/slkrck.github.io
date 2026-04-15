#requires -version 7.5

<#
.SYNOPSIS
Displays a curated, repo-aware tree view of the directory structure.

.DESCRIPTION
Show-RepoTree renders a tree-style view of the repository directory structure with
sensible defaults for infrastructure and automation repositories.

Unlike the native `tree.exe`, this command:
- Excludes common noise directories automatically (e.g. .git, bin, obj, out)
- Understands repository semantics (Azure, Terraform, WinMgmt, build, tests)
- Supports interactive include/exclude selection
- Optionally limits depth and includes files

This command is intended for documentation, README generation, PR reviews,
and architecture discussions where a clean and intentional tree view is required.

.WHAT THIS DOES
- Enumerates the repository directory structure
- Excludes non-semantic or generated directories by default
- Optionally prompts to include or exclude top-level areas
- Optionally limits recursion depth
- Outputs a clean, readable tree view suitable for copy/paste

.REQUIREMENTS
- PowerShell 7.5 or later
- Read access to the repository filesystem

.EXAMPLE
# Show a default repo tree (directories only)
Show-RepoTree

.EXAMPLE
# Interactive mode (choose what to include/exclude)
Show-RepoTree -Interactive

.EXAMPLE
# Limit output depth to 3 levels
Show-RepoTree -MaxDepth 3

.EXAMPLE
# Include files as well as directories
Show-RepoTree -IncludeFiles

.EXAMPLE
# Interactive + depth-limited (ideal for README snippets)
Show-RepoTree -Interactive -MaxDepth 4

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

function Show-RepoTree {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = '.',

        [Parameter()]
        [switch]$IncludeFiles,

        [Parameter()]
        [int]$MaxDepth = 0,   # 0 = unlimited

        [Parameter()]
        [string[]]$DefaultExcludeNames = @(
            '.git','.github','.vscode','.vs',
            'node_modules','bin','obj',
            'out','dist','coverage',
            '.terraform','.terragrunt-cache',
            '__pycache__'
        ),

        [Parameter()]
        [switch]$Interactive
    )

    $root = (Resolve-Path -LiteralPath $Path).Path

    # Top-level directories for interactive selection
    $topDirs = Get-ChildItem -LiteralPath $root -Directory -Force |
        Select-Object -ExpandProperty Name

    $excludeNames = [System.Collections.Generic.List[string]]::new()
    $DefaultExcludeNames | ForEach-Object { [void]$excludeNames.Add($_) }

    if ($Interactive) {
        Write-Host ""
        Write-Host "Top-level folders in repo:"
        $topDirs | ForEach-Object { Write-Host " - $_" }

        Write-Host ""
        Write-Host "Default excludes:"
        Write-Host "  $($DefaultExcludeNames -join ', ')"
        Write-Host ""

        $mode = Read-Host "Mode (E)xclude additional / (I)nclude only top-level / (N)o prompts"
        switch -Regex ($mode) {
            '^(I|i)' {
                $includeOnly = Read-Host "Include ONLY these top-level folders (comma-separated)"
                $includeOnlyList = $includeOnly -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                if ($includeOnlyList.Count -gt 0) {
                    # exclude any top-level not in include list
                    $topDirs | Where-Object { $_ -notin $includeOnlyList } | ForEach-Object { [void]$excludeNames.Add($_) }
                }
            }
            '^(E|e)' {
                $extra = Read-Host "Exclude these folder names (comma-separated)"
                $extraList = $extra -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                $extraList | ForEach-Object { [void]$excludeNames.Add($_) }
            }
            default { }
        }

        # Optional: exclude noisy known subtrees (pattern-based)
        $subtree = Read-Host "Exclude known noisy subtrees? (y/N) e.g. RepoBootstrap/build, RepoBootstrap/tests"
        $excludeSubtrees = $subtree -match '^(y|Y)'
    }
    else {
        $excludeSubtrees = $false
    }

    # Build exclusion regex for folder names
    $excludeNameRegex = if ($excludeNames.Count -gt 0) { ($excludeNames | Sort-Object -Unique | ForEach-Object { [regex]::Escape($_) }) -join '|' } else { $null }

    # Optional exclusion for known noisy subtrees in your repo
    $noisySubtreeRegex = if ($excludeSubtrees) {
        # match path segments (cross-platform)
        '(?i)(\\|/)(RepoBootstrap)(\\|/)(build|tests)(\\|/|$)'
    } else {
        $null
    }

    # Collect all items to render (directories + optionally files)
    $items = Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object {
            if (-not $IncludeFiles -and -not $_.PSIsContainer) { return $false }

            # Depth limiting
            if ($MaxDepth -gt 0) {
                $rel = $_.FullName.Substring($root.Length).TrimStart('\','/')
                $depth = ($rel -split '[\\/]').Count
                if ($depth -gt $MaxDepth) { return $false }
            }

            # Exclude by folder name (any segment)
            if ($excludeNameRegex) {
                $segments = $_.FullName.Substring($root.Length).TrimStart('\','/') -split '[\\/]'
                if ($segments | Where-Object { $_ -match "^(?i)($excludeNameRegex)$" }) { return $false }
            }

            # Exclude known noisy subtrees
            if ($noisySubtreeRegex -and $_.FullName -match $noisySubtreeRegex) { return $false }

            return $true
        } |
        Sort-Object FullName

    # Render a simple tree-like view
    Write-Host ""
    Write-Host (Split-Path -Leaf $root)
    foreach ($it in $items) {
        $rel = $it.FullName.Substring($root.Length).TrimStart('\','/')
        if (-not $rel) { continue }

        $parts = $rel -split '[\\/]'
        $depth = $parts.Count - 1
        $indent = '  ' * $depth

        Write-Host ("{0}|-- {1}" -f $indent, $it.Name)
    }

    Write-Host ""
}
