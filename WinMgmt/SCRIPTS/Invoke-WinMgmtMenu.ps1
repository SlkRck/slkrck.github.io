<#
.SYNOPSIS
Interactive menu-driven entrypoint for WinMgmt operations.

.DESCRIPTION
Provides a simple text-based menu for common WinMgmt tasks.
Designed for operators who prefer guided execution over raw cmdlets.

.WHAT THIS DOES
- Loads WinMgmt module
- Presents an interactive menu
- Collects input safely
- Invokes underlying WinMgmt functions

.REQUIREMENTS
- PowerShell 7+ recommended
- WinRM enabled on targets

.EXAMPLE
.\Invoke-WinMgmtMenu.ps1
#>

$moduleManifest = Resolve-Path (Join-Path $PSScriptRoot '..\Modules\WinMgmt\WinMgmt.psd1')

Remove-Module WinMgmt -Force -ErrorAction SilentlyContinue
Import-Module $moduleManifest -Force -ErrorAction Stop

if (-not (Get-Command Test-WinRmReady -ErrorAction SilentlyContinue)) {
    throw "Module imported but Test-WinRmReady is not available. Verify WinMgmt.psm1 is loading SNIPS\functions."
}

function Read-ComputerNames {
    $input = Read-Host 'Enter computer names (comma-separated)'
    $input -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function Read-YesNo {
    param([string]$Prompt)
    (Read-Host "$Prompt (Y/N)") -match '^(Y|y)$'
}

while ($true) {
    Clear-Host
    Write-Host '=== WinMgmt Menu ==='
    Write-Host '1) Get Network Adapter Info'
    Write-Host '2) Test WinRM Readiness'
    Write-Host '3) Exit'
    Write-Host ''

    switch (Read-Host 'Select an option') {

        '1' {
            $computers = Read-ComputerNames
            if (-not $computers) { Pause; break }

            $useCred = Read-YesNo 'Use alternate credentials?'
            $cred = if ($useCred) { Get-Credential } else { $null }

            $reach = Read-YesNo 'Perform WinRM reachability check?'

            Get-RemoteNetworkAdapterInfo `
                -ComputerName $computers `
                -Credential $cred `
                -ReachabilityCheck:$reach

            Pause
        }

        '2' {
            $computers = Read-ComputerNames
            if (-not $computers) { Pause; break }

            Test-WinRmReady -ComputerName $computers | Format-Table -AutoSize
            Pause
        }

        '3' {
            break MainMenu
        }

        default {
            Write-Host 'Invalid selection.'
            Pause
        }
    }
}
