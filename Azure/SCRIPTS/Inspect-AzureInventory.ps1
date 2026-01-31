    <#
    .SYNOPSIS
    Validates that required Az cmdlets are available and that an Az context exists (or can be created).

    .DESCRIPTION
    Checks for required Az cmdlets needed to gather inventory. Optionally attempts authentication using
    Connect-AzAccount if no context exists and -AutoLogin is provided.

    .PARAMETER AutoLogin
    If set and no Az context exists, attempts Connect-AzAccount to establish a session.

    .PARAMETER IncludeSql
    If set, also requires Az.Sql cmdlets to be available.

    .EXAMPLE
    Assert-AzInventoryPrerequisites -AutoLogin

    .EXAMPLE
    Assert-AzInventoryPrerequisites -AutoLogin -IncludeSql

    .NOTES
    In Azure CloudShell you are usually already authenticated, so -AutoLogin is not typically needed.
    #>

Set-StrictMode -Version Latest

# region: Private helpers

function Test-IsCloudShell {
    [CmdletBinding()]
    param()

    return [bool](
        $env:ACC_CLOUD -or
        ($env:HOME -like '/home/*') -or
        ($env:AZUREPS_HOST_ENVIRONMENT -like '*CloudShell*')
    )
}

function Get-DefaultOutputRoot {
    [CmdletBinding()]
    param()

    if (Test-IsCloudShell) {
        return (Join-Path $env:HOME 'AzureInventory')
    }

    return 'C:\AzureInventory'
}

function Assert-AzInventoryPrerequisites {

    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$AutoLogin,

        [Parameter()]
        [switch]$IncludeSql
    )

    $requiredCmdlets = @(
        'Get-AzContext',
        'Get-AzSubscription',
        'Set-AzContext',
        'Get-AzVM',
        'Get-AzNetworkInterface',
        'Get-AzStorageAccount',
        'Get-AzVirtualNetwork',
        'Get-AzNetworkSecurityGroup',
        'Get-AzLoadBalancer'
    )

    foreach ($c in $requiredCmdlets) {
        if (-not (Get-Command $c -ErrorAction SilentlyContinue)) {
            throw "Missing required cmdlet [$c]. Install/Import Az modules (Az.Accounts/Az.Compute/Az.Network/Az.Storage)."
        }
    }

    if ($IncludeSql) {
        if (-not (Get-Command 'Get-AzSqlServer' -ErrorAction SilentlyContinue)) {
            throw "IncludeSql specified but Az.Sql cmdlets were not found. Install module Az.Sql."
        }
    }

    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        if ($AutoLogin) {
            Connect-AzAccount | Out-Null
            $ctx = Get-AzContext -ErrorAction SilentlyContinue
            if (-not $ctx) {
                throw "Connect-AzAccount completed but no Az context is available."
            }
        }
        else {
            throw "No active Az context. Run Connect-AzAccount or specify -AutoLogin. In CloudShell, you should already be authenticated."
        }
    }

    return $true
}

function New-InventoryFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Export-InventoryCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Data,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    $Data | Export-Csv -Path $Path -NoTypeInformation -Force
}

function Select-TargetSubscriptions {
    <#
    .SYNOPSIS
    Filters Azure subscriptions using include/exclude lists and disabled subscription handling.

    .DESCRIPTION
    Returns subscriptions after applying:
      - IncludeSubscriptionId (whitelist)
      - ExcludeSubscriptionId (blacklist)
      - IncludeDisabledSubscriptions flag (default: disabled are excluded)

    .PARAMETER Subscriptions
    Subscription objects returned from Get-AzSubscription.

    .PARAMETER IncludeSubscriptionId
    Optional whitelist of subscription IDs.

    .PARAMETER ExcludeSubscriptionId
    Optional blacklist of subscription IDs.

    .PARAMETER IncludeDisabledSubscriptions
    If set, Disabled subscriptions are included; otherwise filtered out.

    .EXAMPLE
    $subs = Get-AzSubscription
    Select-TargetSubscriptions -Subscriptions $subs -IncludeSubscriptionId @('...') -IncludeDisabledSubscriptions

    .NOTES
    If both include and exclude lists are used, exclude is applied after include.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Subscriptions,

        [Parameter()]
        [string[]]$IncludeSubscriptionId,

        [Parameter()]
        [string[]]$ExcludeSubscriptionId,

        [Parameter()]
        [switch]$IncludeDisabledSubscriptions
    )

    $filtered = $Subscriptions

    if ($IncludeSubscriptionId) {
        $filtered = $filtered | Where-Object { $IncludeSubscriptionId -contains $_.Id }
    }

    if ($ExcludeSubscriptionId) {
        $filtered = $filtered | Where-Object { $ExcludeSubscriptionId -notcontains $_.Id }
    }

    if (-not $IncludeDisabledSubscriptions) {
        $filtered = $filtered | Where-Object { $_.State -ne 'Disabled' }
    }

    return @($filtered)
}

# endregion: Private helpers

function Get-AzInventoryForSubscription {
    <#
    .SYNOPSIS
    Collects Azure inventory for a single subscription and optionally exports CSV reports.

    .DESCRIPTION
    Sets the Az context to the provided SubscriptionId, collects inventory datasets:
    - Virtual machines (plus best-effort power status and NIC private IPs)
    - NSG custom rules
    - Storage accounts
    - Virtual networks (dynamic subnet columns)
    - Load balancers
    - Optional SQL servers/databases (if -IncludeSql is specified)

    If -NoExport is NOT specified, exports CSVs to OutputPath.

    .PARAMETER SubscriptionId
    The subscription ID to inventory.

    .PARAMETER SubscriptionName
    Optional friendly name (used only for output enrichment).

    .PARAMETER OutputPath
    Where CSV files should be written (required unless -NoExport).

    .PARAMETER IncludeSql
    If set, gathers SQL server/database details (requires Az.Sql).

    .PARAMETER SqlResourceGroupName
    Optional override RG for SQL DB enumeration. Default uses the server's resource group.

    .PARAMETER NoExport
    If set, does not export CSVs; returns inventory objects only.

    .EXAMPLE
    Get-AzInventoryForSubscription -SubscriptionId $sub.Id -SubscriptionName $sub.Name -OutputPath "C:\AzureInventory\$($sub.Id)"

    .EXAMPLE
    Get-AzInventoryForSubscription -SubscriptionId $sub.Id -NoExport -IncludeSql

    .NOTES
    This function is best-effort; it throws on unrecoverable failures but caller can wrap in try/catch.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SubscriptionId,

        [Parameter()]
        [string]$SubscriptionName,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$IncludeSql,

        [Parameter()]
        [string]$SqlResourceGroupName,

        [Parameter()]
        [switch]$NoExport
    )

    if (-not $NoExport -and -not $OutputPath) {
        throw "OutputPath is required unless -NoExport is specified."
    }

    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

    $vms   = Get-AzVM
    $nics  = Get-AzNetworkInterface
    $sas   = Get-AzStorageAccount
    $vnets = Get-AzVirtualNetwork
    $nsgs  = Get-AzNetworkSecurityGroup
    $lbs   = Get-AzLoadBalancer

    # region: VMs
    $vmInventory = foreach ($vm in $vms) {
        $vmStatus = $null
        try {
            $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
        } catch {
            # best-effort, continue
        }

        $vmNicIds   = @($vm.NetworkProfile.NetworkInterfaces.Id)
        $privateIps = foreach ($nic in $nics) {
            if ($vmNicIds -contains $nic.Id) {
                $nic.IpConfigurations.PrivateIpAddress
            }
        } | Where-Object { $_ } | Select-Object -Unique

        $dataDiskNames = @($vm.StorageProfile.DataDisks | ForEach-Object { $_.Name }) -join '; '

        if ($null -eq $vm.StorageProfile.OsDisk.ManagedDisk) {
            $managedOsDiskUri   = 'Unmanaged'
            $unmanagedOsDiskUri = $vm.StorageProfile.OsDisk.Vhd.Uri
        }
        else {
            $managedOsDiskUri   = $vm.StorageProfile.OsDisk.ManagedDisk.Id
            $unmanagedOsDiskUri = 'Managed'
        }

        [pscustomobject]@{
            SubscriptionId      = $SubscriptionId
            SubscriptionName    = $SubscriptionName
            ResourceGroupName   = $vm.ResourceGroupName
            VMName              = $vm.Name
            VMStatus            = ($vmStatus.Statuses | Select-Object -Last 1).DisplayStatus
            Location            = $vm.Location
            VMSize              = $vm.HardwareProfile.VmSize
            OSType              = $vm.StorageProfile.OsDisk.OsType
            ImageSku            = $vm.StorageProfile.ImageReference.Sku
            AdminUserName       = $vm.OSProfile.AdminUsername
            NICIds              = ($vmNicIds -join '; ')
            PrivateIPs          = ($privateIps -join '; ')
            ManagedOSDiskURI    = $managedOsDiskUri
            UnManagedOSDiskURI  = $unmanagedOsDiskUri
            DataDiskNames       = $dataDiskNames
        }
    }
    # endregion

    # region: NSG rules
    $nsgRules = foreach ($nsg in $nsgs) {
        foreach ($rule in @($nsg.SecurityRules)) {
            if (-not $rule) { continue }
            [pscustomobject]@{
                SubscriptionId            = $SubscriptionId
                SubscriptionName          = $SubscriptionName
                ResourceGroupName         = $nsg.ResourceGroupName
                NSGName                   = $nsg.Name
                RuleName                  = $rule.Name
                Priority                  = $rule.Priority
                Protocol                  = $rule.Protocol
                Direction                 = $rule.Direction
                SourcePortRange           = $rule.SourcePortRange
                DestinationPortRange      = $rule.DestinationPortRange
                SourceAddressPrefix       = $rule.SourceAddressPrefix
                DestinationAddressPrefix  = $rule.DestinationAddressPrefix
                Access                    = $rule.Access
            }
        }
    }
    # endregion

    # region: Storage
    $storage = foreach ($sa in $sas) {
        [pscustomobject]@{
            SubscriptionId       = $SubscriptionId
            SubscriptionName     = $SubscriptionName
            ResourceGroupName    = $sa.ResourceGroupName
            StorageAccountName   = $sa.StorageAccountName
            Location             = $sa.Location
            Kind                 = $sa.Kind
            SkuTier              = $sa.Sku.Tier
            ReplicationType      = $sa.Sku.Name
            HttpsTrafficOnly     = $sa.EnableHttpsTrafficOnly
        }
    }
    # endregion

    # region: VNets
    $vnetRows = foreach ($vnet in $vnets) {
        $obj = [ordered]@{
            SubscriptionId    = $SubscriptionId
            SubscriptionName  = $SubscriptionName
            ResourceGroupName = $vnet.ResourceGroupName
            Location          = $vnet.Location
            VNETName          = $vnet.Name
        }

        $i = 1
        foreach ($sn in @($vnet.Subnets)) {
            $obj["Subnet$i"]             = $sn.Name
            $obj["SubnetAddressSpace$i"] = $sn.AddressPrefix
            $i++
        }

        [pscustomobject]$obj
    }
    # endregion

    # region: Load Balancers
    $lbRows = foreach ($lb in $lbs) {
        $obj = [ordered]@{
            SubscriptionId               = $SubscriptionId
            SubscriptionName             = $SubscriptionName
            ResourceGroupName            = $lb.ResourceGroupName
            Name                         = $lb.Name
            Location                     = $lb.Location
            FrontendIpConfigurationsName = ($lb.FrontendIpConfigurations.Name -join '; ')
            BackendAddressPoolsName      = ($lb.BackendAddressPools.Name -join '; ')
        }

        $poolIps = @($lb.BackendAddressPools.BackendIpConfigurations)
        if ($poolIps) {
            $j = 1
            foreach ($ip in $poolIps) {
                if (-not $ip) { continue }
                $obj["BackendPoolMemberId$j"] = $ip.Id
                $j++
            }
        }

        [pscustomobject]$obj
    }
    # endregion

    # region: SQL (optional)
    $sqlRows = @()
    if ($IncludeSql) {
        try {
            $servers = Get-AzSqlServer
            foreach ($svr in $servers) {
                try {
                    $rg = if ($SqlResourceGroupName) { $SqlResourceGroupName } else { $svr.ResourceGroupName }
                    $dbs = Get-AzSqlDatabase -ServerName $svr.ServerName -ResourceGroupName $rg
                    foreach ($db in $dbs) {
                        $sqlRows += [pscustomobject]@{
                            SubscriptionId    = $SubscriptionId
                            SubscriptionName  = $SubscriptionName
                            ResourceGroupName = $db.ResourceGroupName
                            SQLServerName     = $db.ServerName
                            DatabaseName      = $db.DatabaseName
                            Location          = $db.Location
                            ElasticPool       = $db.ElasticPoolName
                            Status            = $db.Status
                        }
                    }
                } catch {
                    # best-effort
                }
            }
        } catch {
            # best-effort
        }
    }
    # endregion

    if (-not $NoExport) {
        New-InventoryFolder -Path $OutputPath | Out-Null

        Export-InventoryCsv -Data $vmInventory -Path (Join-Path $OutputPath 'Virtual_Machine_details.csv')
        if ($nsgRules) { Export-InventoryCsv -Data $nsgRules -Path (Join-Path $OutputPath 'nsg_custom_rules_details.csv') }
        Export-InventoryCsv -Data $storage  -Path (Join-Path $OutputPath 'Storage_Account_Details.csv')
        Export-InventoryCsv -Data $vnetRows -Path (Join-Path $OutputPath 'Virtual_networks_details.csv')
        Export-InventoryCsv -Data $lbRows   -Path (Join-Path $OutputPath 'Azure_Load_Balancer_details.csv')
        if ($sqlRows) { Export-InventoryCsv -Data $sqlRows -Path (Join-Path $OutputPath 'SQLServer_Details.csv') }
    }

    return [pscustomobject]@{
        VirtualMachines = $vmInventory
        NsgCustomRules  = $nsgRules
        StorageAccounts = $storage
        VirtualNetworks = $vnetRows
        LoadBalancers   = $lbRows
        SqlDatabases    = $sqlRows
    }
}

function Invoke-AzInventory {
    <#
    .SYNOPSIS
    Generates Azure inventory across subscriptions and exports per-subscription CSV files.

    .DESCRIPTION
    Performs prerequisite checks, enumerates subscriptions, applies filtering, and for each selected
    subscription collects inventory via Get-AzInventoryForSubscription. Results are exported under
    OutputRoot\<SubscriptionId>\*.csv

    .PARAMETER OutputRoot
    Root output folder. If not specified, defaults to:
      - CloudShell: $HOME/AzureInventory
      - Local: C:\AzureInventory

    .PARAMETER IncludeSubscriptionId
    Optional whitelist of subscription IDs to inventory.

    .PARAMETER ExcludeSubscriptionId
    Optional blacklist of subscription IDs to exclude.

    .PARAMETER IncludeDisabledSubscriptions
    Include subscriptions in 'Disabled' state. Default is to exclude disabled subscriptions.

    .PARAMETER AutoLogin
    If no Az context exists, attempts Connect-AzAccount.

    .PARAMETER IncludeSql
    Also gather SQL server/database inventory (requires Az.Sql).

    .PARAMETER SqlResourceGroupName
    Optional override for SQL DB enumeration. Default uses the server's resource group.

    .EXAMPLE
    Invoke-AzInventory -Verbose

    .EXAMPLE
    Invoke-AzInventory -OutputRoot (Join-Path $HOME 'AzureInventory') -IncludeSql -Verbose

    .EXAMPLE
    Invoke-AzInventory -IncludeSubscriptionId @('subid1','subid2') -Verbose

    .OUTPUTS
    PSCustomObject per subscription indicating Success/Error and output location.

    .NOTES
    Execution is best-effort per subscription; errors in one subscription do not stop processing others.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$OutputRoot,

        [Parameter()]
        [string[]]$IncludeSubscriptionId,

        [Parameter()]
        [string[]]$ExcludeSubscriptionId,

        [Parameter()]
        [switch]$IncludeDisabledSubscriptions,

        [Parameter()]
        [switch]$AutoLogin,

        [Parameter()]
        [switch]$IncludeSql,

        [Parameter()]
        [string]$SqlResourceGroupName
    )

    if (-not $OutputRoot) {
        $OutputRoot = Get-DefaultOutputRoot
    }

    Assert-AzInventoryPrerequisites -AutoLogin:$AutoLogin -IncludeSql:$IncludeSql | Out-Null
    New-InventoryFolder -Path $OutputRoot | Out-Null

    $subs = Get-AzSubscription

    $targets = Select-TargetSubscriptions `
        -Subscriptions $subs `
        -IncludeSubscriptionId $IncludeSubscriptionId `
        -ExcludeSubscriptionId $ExcludeSubscriptionId `
        -IncludeDisabledSubscriptions:$IncludeDisabledSubscriptions

    if (-not $targets -or $targets.Count -eq 0) {
        Write-Warning "No subscriptions matched the provided filters."
        return @()
    }

    $results = foreach ($sub in $targets) {
        $subOut = Join-Path $OutputRoot $sub.Id

        try {
            Write-Verbose "Processing subscription: $($sub.Name) ($($sub.Id)) State=$($sub.State)"

            $null = Get-AzInventoryForSubscription `
                -SubscriptionId $sub.Id `
                -SubscriptionName $sub.Name `
                -OutputPath $subOut `
                -IncludeSql:$IncludeSql `
                -SqlResourceGroupName $SqlResourceGroupName `
                -NoExport:$false

            [pscustomobject]@{
                SubscriptionId   = $sub.Id
                SubscriptionName = $sub.Name
                OutputPath       = $subOut
                Success          = $true
                Error            = $null
            }
        }
        catch {
            Write-Warning "Failed subscription $($sub.Name) ($($sub.Id)): $($_.Exception.Message)"
            [pscustomobject]@{
                SubscriptionId   = $sub.Id
                SubscriptionName = $sub.Name
                OutputPath       = $subOut
                Success          = $false
                Error            = $_.Exception.Message
            }
        }
    }

    return $results
}

Export-ModuleMember -Function @(
    'Invoke-AzInventory',
    'Get-AzInventoryForSubscription'
)
