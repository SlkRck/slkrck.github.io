<#
👉 This file is never run directly.
It is dot-sourced by build scripts.

#>

Set-StrictMode -Version Latest

function Get-GitVersion {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RepoRoot = (Get-Location).Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$TagPrefix = 'v'
    )

    Push-Location $RepoRoot
    try {
        $git = Get-Command git -ErrorAction SilentlyContinue
        if (-not $git) { return '0.0.0' }

        $raw = (& git describe --tags --dirty --always 2>$null)
        if (-not $raw) { return '0.0.0' }

        $raw = $raw.Trim()

        $isDirty = $raw -match 'dirty$'
        $clean = $raw -replace '-dirty$',''

        if ($clean.StartsWith($TagPrefix)) { $clean = $clean.Substring($TagPrefix.Length) }

        # if it doesn't contain a semver core, treat it as sha-only
        if ($clean -notmatch '\d+\.\d+\.\d+') {
            $ver = "0.0.0+$clean"
        }
        else {
            # Convert "1.2.3-4-gabcdef" -> "1.2.3+4.gabcdef"
            if ($clean -match '^(\d+\.\d+\.\d+)-(\d+)-g([0-9a-fA-F]+)$') {
                $ver = "$($Matches[1])+$($Matches[2]).g$($Matches[3])"
            } else {
                $ver = $clean
            }
        }

        if ($isDirty) { $ver = "$ver.dirty" }
        return $ver
    }
    finally {
        Pop-Location
    }
}

function Update-CommentHelpVersionBlock {
    <#
    .SYNOPSIS
    Updates the value beneath ".VERSION" in a PowerShell comment-help block.

    .DESCRIPTION
    Finds the first occurrence of:
      .VERSION
      <value>
    and replaces <value> with the supplied version string.

    .WHAT THIS DOES
    - Loads the file as raw text
    - Regex-replaces the first ".VERSION" value
    - Writes the file back with UTF-8 encoding

    .REQUIREMENTS
    - Target file must contain a ".VERSION" entry.

    .EXAMPLE
    Update-CommentHelpVersionBlock -Path .\WinMgmt\SCRIPTS\Show-SystemStatus.ps1 -Version 1.2.3

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
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter()]
        [ValidateSet('utf8','utf8BOM')]
        [string]$Encoding = 'utf8'
    )

    $content = Get-Content -LiteralPath $Path -Raw

    # Replace the first value directly under ".VERSION"
    # Supports:
    # .VERSION
    #   1.2.3
    $pattern = '(?ms)(\.VERSION\s*\R)(\s*)([^\r\n]+)'

    if ($content -notmatch $pattern) {
        throw "No .VERSION block found in: $Path"
    }

    $new = [regex]::Replace($content, $pattern, {
        param($m)
        $m.Groups[1].Value + $m.Groups[2].Value + $Version
    }, 1)

    if ($PSCmdlet.ShouldProcess($Path, "Update .VERSION to $Version")) {
        Set-Content -LiteralPath $Path -Value $new -Encoding $Encoding
    }
}

function Convert-ToPsModuleVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )

    # Convert SemVer-ish to PowerShell [version] compatible "a.b.c"
    # Strip build metadata (+...) and ".dirty"
    $core = ($Version -split '\+')[0] -replace '\.dirty$',''

    if ($core -notmatch '^\d+\.\d+\.\d+$') {
        throw "Version '$Version' cannot be converted to PowerShell module version 'a.b.c'."
    }

    return $core
}

function Update-ModuleManifestVersion {
    <#
    .SYNOPSIS
    Updates ModuleVersion in a PowerShell module manifest (.psd1).

    .DESCRIPTION
    Converts a SemVer-ish version string into a PowerShell-compatible module version (a.b.c),
    then updates the manifest ModuleVersion using Update-ModuleManifest.

    .WHAT THIS DOES
    - Normalizes a version like 1.2.3+4.gabc.dirty -> 1.2.3
    - Updates ModuleVersion in the manifest

    .REQUIREMENTS
    - Update-ModuleManifest available
    - Version must be convertible to a.b.c

    .EXAMPLE
    Update-ModuleManifestVersion -ManifestPath .\WinMgmt\WinMgmt.psd1 -Version 1.2.3+4.gabc

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
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )

    $moduleVersion = Convert-ToPsModuleVersion -Version $Version

    if ($PSCmdlet.ShouldProcess($ManifestPath, "Update ModuleVersion to $moduleVersion")) {
        Update-ModuleManifest -Path $ManifestPath -ModuleVersion $moduleVersion
    }
}
