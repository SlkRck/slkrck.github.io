#requires -Version 7.0
# Pester v5 test
# Enforces mandatory README Header (comment-based help) at the top of every .ps1 / .psm1 file

BeforeAll {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Repo root = parent of /tests
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..') |
        Select-Object -ExpandProperty Path

    # File types to enforce
    $script:TargetExtensions = @('.ps1', '.psm1')

    # Paths to exclude from enforcement (regex)
    # Adjust as needed
    $script:ExcludePathRegex = @(
        '\\\.git\\',
        '\\node_modules\\',
        '\\bin\\',
        '\\obj\\',
        '\\dist\\',
        '\\out\\',
        '\\vendor\\',
        '\\.vscode\\',
        '\\.github\\',
        '\\sandbox-repo\\'
    ) -join '|'

    function Get-TargetFiles {
        Get-ChildItem -Path $script:RepoRoot -Recurse -File |
            Where-Object {
                $script:TargetExtensions -contains $_.Extension.ToLowerInvariant()
            } |
            Where-Object {
                $_.FullName -notmatch $script:ExcludePathRegex
            }
    }

    function Get-FileText {
        param([Parameter(Mandatory)][string]$Path)
        Get-Content -LiteralPath $Path -Raw
    }

    function Test-HasRequiredHeader {
        param([Parameter(Mandatory)][string]$Text)

        # Must start with comment-based help
        $trimmed = $Text.TrimStart()
        if (-not $trimmed.StartsWith('<#')) {
            return $false
        }

        # Required sections
        $requiredTokens = @(
            '.SYNOPSIS',
            '.DESCRIPTION',
            '.EXAMPLES'
        )

        foreach ($token in $requiredTokens) {
            if ($trimmed -notmatch [regex]::Escape($token)) {
                return $false
            }
        }

        return $true
    }

    function Get-HeaderFailureReason {
        param([Parameter(Mandatory)][string]$Text)

        $trimmed = $Text.TrimStart()

        if (-not $trimmed.StartsWith('<#')) {
            return "Missing top-of-file '<#' README header."
        }
        if ($trimmed -notmatch '\.SYNOPSIS') {
            return "Missing required section: .SYNOPSIS"
        }
        if ($trimmed -notmatch '\.DESCRIPTION') {
            return "Missing required section: .DESCRIPTION"
        }
        if ($trimmed -notmatch '\.EXAMPLES') {
            return "Missing required section: .EXAMPLES"
        }

        return "README header validation failed."
    }
}

Describe 'README Header Compliance' {

    It 'All PowerShell scripts and modules must have a README header at the top of the file' {

        $files = Get-TargetFiles
        $files.Count | Should -BeGreaterThan 0

        $failures = foreach ($file in $files) {
            $text = Get-FileText -Path $file.FullName

            if (-not (Test-HasRequiredHeader -Text $text)) {
                [pscustomobject]@{
                    File   = $file.FullName.Replace(
                        $script:RepoRoot + [IO.Path]::DirectorySeparatorChar,
                        ''
                    )
                    Reason = Get-HeaderFailureReason -Text $text
                }
            }
        }

        if ($failures) {
            $message = "README Header compliance failures:`n" +
                       ($failures | ForEach-Object {
                           " - $($_.File): $($_.Reason)"
                        } | Out-String)

            throw $message
        }
    }
}
