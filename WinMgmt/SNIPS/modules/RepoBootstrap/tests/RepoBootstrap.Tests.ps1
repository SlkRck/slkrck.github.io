# Requires Pester 5+
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleRoot = Split-Path -Parent $here
$psd1 = Join-Path $moduleRoot 'RepoBootstrap.psd1'

Import-Module $psd1 -Force

Describe "RepoBootstrap" {
    It "Exports Invoke-RepoStructureBootstrap" {
        (Get-Command Invoke-RepoStructureBootstrap -ErrorAction Stop).Name | Should -Be 'Invoke-RepoStructureBootstrap'
    }

    It "Supports -WhatIf without throwing (command surface test)" {
        { Invoke-RepoStructureBootstrap -WhatIf -NoPush } | Should -Not -Throw
    }
}
