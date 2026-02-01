<#
.SYNOPSIS
Automatically inserts a standardized README header into PowerShell scripts and modules.

.DESCRIPTION
This script scans PowerShell files (.ps1 and .psm1) and checks whether they begin
with a comment-based README header. If a header is missing, a standardized header
template is inserted at the top of the file.

The operation is idempotent and will not modify files that already contain a header.

.WHAT THIS DOES
- Scans .ps1 and .psm1 files
- Detects missing comment-based help headers
- Inserts a standardized README header template
- Skips files that already comply

.REQUIREMENTS
- PowerShell 7+ or Windows PowerShell 5.1
- Write access to target files

.PARAMETER Path
Root path to scan recursively.

.PARAMETER WhatIf
Shows what would be modified without changing files.

.EXAMPLE
Insert headers into all scripts under the current directory.
.\Insert-ReadmeHeader.ps1 -Path .

.EXAMPLE
Preview changes without modifying files.
.\Insert-ReadmeHeader.ps1 -Path . -WhatIf

.NOTES
- Intended to work with Pester style enforcement
- Header content is intentionally generic and should be customized per script

.LINK
https://learn.microsoft.com/powershell/scripting/developer/help/comment-based-help
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Path
)

$headerTemplate = @'
<#
.SYNOPSIS
<Short description of the script or module.>

.DESCRIPTION
<Detailed explanation of what this script or module does and why it exists.>

.WHAT THIS DOES
- Describe major actions performed

.REQUIREMENTS
- PowerShell version
- Required modules
- Permissions or prerequisites

.EXAMPLE
<Provide at least one usage example.>

.NOTES
    Author:
    Version:
    Date:
#>

'@

Get-ChildItem -Path $Path -Recurse -File |
    Where-Object { $_.Extension -in '.ps1', '.psm1' } |
    ForEach-Object {

        $content = Get-Content -LiteralPath $_.FullName -Raw

        if ($content.TrimStart().StartsWith('<#')) {
            return
        }

        if ($PSCmdlet.ShouldProcess($_.FullName, 'Insert README header')) {
            Set-Content -LiteralPath $_.FullName -Value ($headerTemplate + $content) -Encoding UTF8
            Write-Verbose "Inserted header into $($_.FullName)"
        }
    }
