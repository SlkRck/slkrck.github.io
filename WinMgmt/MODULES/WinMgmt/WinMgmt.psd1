@{
    RootModule        = 'WinMgmt.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b0c1c7d4-0a8e-4d58-9b5b-2d9c9f2a9e01'
    Author            = 'Richard Taylor'
    Copyright         = '(c) 2026 Richard Taylor'
    Description       = 'Windows management and WinRM-based operational utilities.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-RemoteNetworkAdapterInfo',
        'Test-WinRmReady',
        'New-WinRmCimSession',
        'Remove-SafeCimSession',
        'Assert-RunningAsAdmin'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('WinRM','CIM','Windows','Management')
            ProjectUri = 'https://github.com/SlkRck/slkrck.github.io'
        }
    }
}
