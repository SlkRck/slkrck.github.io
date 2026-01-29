@{
    RootModule        = 'RepoBootstrap.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b5c6a7c2-8f7e-4d48-a34d-2a2f0c0b1c22'
    Author            = 'Rick Taylor'
    
    Copyright         = '(c) SLKRCK. All rights reserved.'
    Description       = 'Bootstraps an existing GitHub repo locally and standardizes folder structure + README TOC.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('Invoke-RepoStructureBootstrap')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('GitHub', 'gh', 'git', 'bootstrap', 'repo')
            LicenseUri = ''
            ProjectUri = ''
        }
    }
}
