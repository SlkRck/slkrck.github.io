function Show-DirectoryTree {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = '.',

        [string[]]$Exclude = @('.git', 'node_modules', 'bin', 'obj'),

        [switch]$IncludeFiles
    )

    $root = Resolve-Path $Path

    Get-ChildItem -Path $root -Recurse -Force |
        Where-Object {
            # Exclude directories by name
            $_.FullName -notmatch ($Exclude -join '|') -and
            ($IncludeFiles -or $_.PSIsContainer)
        } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($root.Path.Length).TrimStart('\','/')
            $depth = ($relative -split '[\\/]').Count - 1
            (' ' * ($depth * 2)) + '|-- ' + $_.Name
        }
}
