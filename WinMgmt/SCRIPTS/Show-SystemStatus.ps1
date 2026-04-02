#requires -version 7.5

<#
.SYNOPSIS
Displays a rich, console-based system status dashboard for a local or remote Windows computer using pwshSpectreConsole.

.DESCRIPTION
Show-SpectreSystemStatus collects system information via CIM/WMI and renders it as a visually rich, structured dashboard in the terminal using pwshSpectreConsole.

The dashboard includes:
- Disk usage (C:) breakdown
- Physical memory usage
- Operating system details
- Hardware identification
- System uptime
- Counts of running processes and services
- Top memory-consuming processes

The function supports local and remote execution, optional credentials, module bootstrapping (online/internal/offline), and graceful handling of optional assets (such as logo images) that may not exist when running from untitled editors or interactive sessions.

.WHAT THIS DOES
- Ensures the pwshSpectreConsole module is available (auto-installs if missing)
- Performs a fast PSGallery route preflight to fail quickly when no outbound route exists
- Falls back to an offline module path when internet access is unavailable
- Queries system state using CIM/WMI (local or remote)
- Renders charts, tables, and panels using Spectre Console formatting
- Optionally displays a logo image if available
- Cleans up CIM sessions reliably via try/finally

.REQUIREMENTS
- PowerShell 7.5 or later
- Windows (CIM/WMI-based queries)
- pwshSpectreConsole module
  - Automatically installed from PSGallery by default
  - Can be supplied via an internal repository or offline module path (folder or zip)

.EXAMPLE
# Local system
Show-SpectreSystemStatus

.EXAMPLE
# Remote system
Show-SpectreSystemStatus -ComputerName SERVER01

.EXAMPLE
# Remote system with credentials
Show-SpectreSystemStatus -ComputerName SERVER01 -Credential (Get-Credential)

.EXAMPLE
# Offline module usage (no internet)
Show-SpectreSystemStatus -SpectreOfflinePath 'C:\Packages\pwshSpectreConsole.zip'

.EXAMPLE
# Suppress pwshSpectreConsole encoding warning (session only)
Show-SpectreSystemStatus -SuppressSpectreEncodingWarning

.NOTES
  .AUTHOR
  Jeff Hicks (original concept); extended and hardened by Richard Taylor (@slkrck)

  .DATE CREATED
  2026-02-02

  .VERSION
  0.0.0

  .LICENSE
  MIT License
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Private helper functions

function Test-PSGalleryRoute {
    <#
    .SYNOPSIS
    Performs a fast connectivity preflight to PSGallery endpoints.

    .DESCRIPTION
    Detects "no route to PSGallery" quickly by validating:
    1) DNS resolution
    2) TCP connectivity to 443
    3) A short HTTPS probe to /api/v2/

    .WHAT THIS DOES
    - Returns a diagnostic object describing which stage failed (dns/tcp/https) and the failure message.

    .REQUIREMENTS
    - Outbound DNS + TCP 443 + HTTPS for successful PSGallery access.

    .EXAMPLE
    Test-PSGalleryRoute

    .NOTES
      .AUTHOR
      Richard Taylor

      .DATE CREATED
      2026-02-02

      .VERSION
      0.0.0

      .LICENSE
      MIT License
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$HostName = 'www.powershellgallery.com',

        [Parameter()]
        [ValidateRange(1,30)]
        [int]$TimeoutSeconds = 2
    )

    $result = [pscustomobject]@{
        HostName        = $HostName
        DnsOk           = $false
        Tcp443Ok        = $false
        HttpsApiOk      = $false
        FailureStage    = $null
        FailureMessage  = $null
    }

    # 1) DNS
    try {
        [void][System.Net.Dns]::GetHostEntry($HostName)
        $result.DnsOk = $true
    }
    catch {
        $result.FailureStage = 'dns'
        $result.FailureMessage = $_.Exception.Message
        return $result
    }

    # 2) TCP 443 (quick)
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $iar = $client.BeginConnect($HostName, 443, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            $client.Close()
            $result.FailureStage = 'tcp'
            $result.FailureMessage = "Timed out connecting to $HostName:443 after ${TimeoutSeconds}s."
            return $result
        }
        $client.EndConnect($iar)
        $client.Close()
        $result.Tcp443Ok = $true
    }
    catch {
        $result.FailureStage = 'tcp'
        $result.FailureMessage = $_.Exception.Message
        return $result
    }

    # 3) HTTPS API probe (short timeout)
    try {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $http = [System.Net.Http.HttpClient]::new($handler)
        $http.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

        $uri = [Uri]("https://$HostName/api/v2/")
        $resp = $http.GetAsync($uri).GetAwaiter().GetResult()
        $result.HttpsApiOk = $resp.IsSuccessStatusCode

        if (-not $result.HttpsApiOk) {
            $result.FailureStage = 'https'
            $result.FailureMessage = "HTTPS request returned status code: $([int]$resp.StatusCode) ($($resp.ReasonPhrase))."
        }

        $http.Dispose()
    }
    catch {
        $result.FailureStage = 'https'
        $result.FailureMessage = $_.Exception.Message
        return $result
    }

    return $result
}

function Initialize-pwshSpectreConsole {
    <#
    .SYNOPSIS
    Ensures pwshSpectreConsole is installed and imported.

    .DESCRIPTION
    Bootstraps the pwshSpectreConsole module for the current session by importing an existing installation,
    installing from a PowerShell repository (PSGallery or internal), or importing from an offline folder/zip.

    .WHAT THIS DOES
    - Imports pwshSpectreConsole if already available
    - Optionally registers a repository if missing (internal repo scenario)
    - Optionally fails fast if PSGallery route is unavailable
    - Installs the module if needed
    - Falls back to offline import when provided

    .REQUIREMENTS
    - Install-Module must be available for online install (PowerShellGet)
    - OfflinePath must be provided for OfflineOnly mode

    .EXAMPLE
    Initialize-pwshSpectreConsole

    .EXAMPLE
    Initialize-pwshSpectreConsole -Repository 'MyInternalPSRepo' -SourceLocation 'https://repo.contoso.com/nuget/powershell' -TrustRepository

    .EXAMPLE
    Initialize-pwshSpectreConsole -OfflineOnly -OfflinePath 'C:\Packages\pwshSpectreConsole.zip'

    .NOTES
      .AUTHOR
      Richard Taylor

      .DATE CREATED
      2026-02-02

      .VERSION
      0.0.0

      .LICENSE
      MIT License
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName = 'pwshSpectreConsole',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Repository = 'PSGallery',

        [Parameter()]
        [string]$SourceLocation,

        [Parameter()]
        [string]$OfflinePath,

        [Parameter()]
        [ValidateSet('CurrentUser','AllUsers')]
        [string]$Scope = 'CurrentUser',

        [Parameter()]
        [version]$MinimumVersion,

        [Parameter()]
        [version]$RequiredVersion,

        [Parameter()]
        [switch]$TrustRepository,

        [Parameter()]
        [switch]$OfflineOnly,

        # Default to fast-fail when using PSGallery to avoid long hang/timeouts.
        [Parameter()]
        [switch]$FastFailPSGallery = $true,

        [Parameter()]
        [ValidateRange(1,30)]
        [int]$PSGalleryTimeoutSeconds = 2
    )

    # Already loaded?
    if (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) { return }

    # Already installed somewhere?
    $available = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending

    if ($RequiredVersion) {
        $available = $available | Where-Object Version -eq $RequiredVersion
    }
    elseif ($MinimumVersion) {
        $available = $available | Where-Object Version -ge $MinimumVersion
    }

    $best = $available | Select-Object -First 1
    if ($best) {
        Import-Module -Name $best.Name -RequiredVersion $best.Version -ErrorAction Stop
        return
    }

    function Import-FromOffline {
        param([Parameter(Mandatory)][string]$Path)

        if (-not (Test-Path -LiteralPath $Path)) {
            throw "OfflinePath not found: $Path"
        }

        $resolved = (Resolve-Path -LiteralPath $Path).Path

        if ($resolved -match '\.zip$') {
            $destRoot = Join-Path $env:USERPROFILE ".local\modules"
            if ($PSCmdlet.ShouldProcess("Expand '$resolved' to '$destRoot'")) {
                New-Item -ItemType Directory -Path $destRoot -Force | Out-Null
                Expand-Archive -Path $resolved -DestinationPath $destRoot -Force
            }

            $candidate = Get-ChildItem -Path $destRoot -Recurse -Filter "$ModuleName.psd1" -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -First 1

            if (-not $candidate) {
                throw "Could not locate '$ModuleName.psd1' after expanding '$resolved' into '$destRoot'."
            }

            Import-Module -Name $candidate.FullName -ErrorAction Stop
            return
        }

        if (Test-Path (Join-Path $resolved "$ModuleName.psd1")) {
            Import-Module -Name (Join-Path $resolved "$ModuleName.psd1") -ErrorAction Stop
            return
        }

        $manifest = Get-ChildItem -Path $resolved -Recurse -Filter "$ModuleName.psd1" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($manifest) {
            Import-Module -Name $manifest.FullName -ErrorAction Stop
            return
        }

        throw "OfflinePath '$resolved' did not contain a '$ModuleName.psd1' manifest."
    }

    # Offline-only mode
    if ($OfflineOnly) {
        if (-not $OfflinePath) { throw "OfflineOnly was specified but no -OfflinePath was provided." }
        Import-FromOffline -Path $OfflinePath
        return
    }

    # Install-Module availability
    $installCmd = Get-Command Install-Module -ErrorAction SilentlyContinue
    if (-not $installCmd) {
        if ($OfflinePath) { Import-FromOffline -Path $OfflinePath; return }
        throw "Install-Module is not available, and no OfflinePath was provided. Install PowerShellGet/PSResourceGet or provide OfflinePath."
    }

    # Ensure repository exists; optionally register internal repo
    $repo = Get-PSRepository -Name $Repository -ErrorAction SilentlyContinue
    if (-not $repo) {
        if ($SourceLocation) {
            $policy = if ($TrustRepository) { 'Trusted' } else { 'Untrusted' }
            if ($PSCmdlet.ShouldProcess("Register PSRepository '$Repository' -> '$SourceLocation' (Policy=$policy)")) {
                Register-PSRepository -Name $Repository -SourceLocation $SourceLocation `
                    -InstallationPolicy $policy -ErrorAction Stop
            }
        }
        else {
            if ($OfflinePath) { Import-FromOffline -Path $OfflinePath; return }
            throw "Repository '$Repository' not found and no SourceLocation/OfflinePath provided."
        }
    }

    # Fast-fail PSGallery route check so we don't hang on long timeouts
    if ($FastFailPSGallery -and $Repository -eq 'PSGallery') {
        $route = Test-PSGalleryRoute -TimeoutSeconds $PSGalleryTimeoutSeconds
        if (-not ($route.DnsOk -and $route.Tcp443Ok -and $route.HttpsApiOk)) {
            if ($OfflinePath) {
                Import-FromOffline -Path $OfflinePath
                return
            }

            $msg = "No route to PSGallery (failed at '$($route.FailureStage)'): $($route.FailureMessage)"
            throw $msg
        }
    }

    $installSplat = @{
        Name        = $ModuleName
        Repository  = $Repository
        Scope       = $Scope
        Force       = $true
        ErrorAction = 'Stop'
    }

    if ($RequiredVersion) {
        $installSplat.RequiredVersion = $RequiredVersion
    }
    elseif ($MinimumVersion) {
        $installSplat.MinimumVersion  = $MinimumVersion
    }

    try {
        if ($PSCmdlet.ShouldProcess("Install '$ModuleName' from '$Repository' (Scope=$Scope)")) {
            Install-Module @installSplat
        }
        Import-Module -Name $ModuleName -ErrorAction Stop
        return
    }
    catch {
        if ($OfflinePath) { Import-FromOffline -Path $OfflinePath; return }
        throw
    }
}

#endregion Private helper functions

#region Public command

function Show-SpectreSystemStatus {
    <#
    .SYNOPSIS
    Renders a Spectre-based system status dashboard for a local or remote Windows computer.

    .DESCRIPTION
    Queries disk, memory, OS, hardware, uptime, services, and processes using CIM/WMI and renders the results using pwshSpectreConsole components (charts, tables, and panels).

    .WHAT THIS DOES
    - Bootstraps pwshSpectreConsole if not present (install/import)
    - Collects system status using CIM/WMI
    - Produces terminal-friendly visuals (charts/tables/panels)
    - Returns a Spectre.Console.Panel object for display

    .REQUIREMENTS
    - PowerShell 7.5+
    - Windows
    - pwshSpectreConsole module (bootstrapped automatically unless OfflineOnly is used without OfflinePath)

    .EXAMPLE
    Show-SpectreSystemStatus

    .EXAMPLE
    Show-SpectreSystemStatus -ComputerName SERVER01

    .EXAMPLE
    Show-SpectreSystemStatus -ComputerName SERVER01 -Credential (Get-Credential)

    .EXAMPLE
    Show-SpectreSystemStatus -SpectreOfflinePath 'C:\Packages\pwshSpectreConsole.zip'

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
    [CmdletBinding()]
    [OutputType('Spectre.Console.Panel')]
    [Alias("sss")]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias("CN")]
        [string]$ComputerName,

        [Parameter(Position=1)]
        [ValidateNotNullOrEmpty()]
        [Alias("RunAs")]
        [PSCredential]$Credential,

        [Parameter(HelpMessage="Specify a logo image (optional). If omitted, attempts MsPowerShell.png in script folder or current directory.")]
        [ValidateScript({ -not $_ -or (Test-Path $_) })]
        [AllowNull()]
        [string]$Logo,

        # Offline support for pwshSpectreConsole module (folder or zip)
        [Parameter()]
        [string]$SpectreOfflinePath,

        # Suppress PwshSpectreConsole encoding warning for current session
        [Parameter()]
        [switch]$SuppressSpectreEncodingWarning
    )

    if ($SuppressSpectreEncodingWarning) {
        $env:IgnoreSpectreEncoding = $true
    }

    # Ensure pwshSpectreConsole is available (PSGallery by default; falls back to offline path if provided)
    Initialize-pwshSpectreConsole -OfflinePath $SpectreOfflinePath -ErrorAction Stop

    $cimSession = $null
    $targetName = $ComputerName

    try {
        if ($PSBoundParameters.ContainsKey('ComputerName')) {
            $cimSplat = @{ ComputerName = $ComputerName }
            if ($PSBoundParameters.ContainsKey('Credential')) { $cimSplat.Credential = $Credential }

            $cimSession = New-CimSession @cimSplat -ErrorAction Stop
            $cimArg = @{ CimSession = $cimSession }
        }
        else {
            $targetName = $env:COMPUTERNAME
            $cimArg = @{ ComputerName = $targetName }
        }

        # Get the data
        $cDrive = Get-CimInstance Win32_LogicalDisk -Property Size,FreeSpace -Filter "DeviceID='C:'" @cimArg
        $os     = Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory,TotalVisibleMemorySize,LastBootUpTime,Caption,OSArchitecture @cimArg
        $svc    = Get-CimInstance Win32_Service -Filter "State='Running'" -Property Name @cimArg
        $cs     = Get-CimInstance Win32_ComputerSystem -Property SystemFamily,Manufacturer,Model @cimArg
        $proc   = Get-CimInstance Win32_Process -Property ProcessID,Name,WorkingSetSize,CreationDate @cimArg

        # Link (host supports links in some terminals)
        $link = Write-SpectreHost "[chartreuse1 italic link=https://jdhitsolutions.com/yourls/newsletter]Click to expand your PowerShell skills[/]" -PassThru |
            Format-SpectrePadded -Top 1 -Left 1 -Bottom 0 -Right 0

        # Resolve a default logo only if we have a real script root (and optionally from current directory)
        $defaultLogo = $null
        if ($PSScriptRoot) {
            $candidate = Join-Path $PSScriptRoot 'MsPowerShell.png'
            if (Test-Path -LiteralPath $candidate) { $defaultLogo = $candidate }
        }
        if (-not $defaultLogo) {
            $cwdCandidate = Join-Path (Get-Location).Path 'MsPowerShell.png'
            if (Test-Path -LiteralPath $cwdCandidate) { $defaultLogo = $cwdCandidate }
        }

        # Prefer explicitly supplied -Logo; else fall back to defaultLogo; else no logo
        $logoPath = if ($Logo) { $Logo } else { $defaultLogo }

        $logoImage = $null
        if ($logoPath -and (Test-Path -LiteralPath $logoPath)) {
            $resolvedLogo = (Resolve-Path -LiteralPath $logoPath).Path
            $logoImage = Get-SpectreImage $resolvedLogo -MaxWidth 10 |
                Format-SpectrePadded -Left 15 -Top 1 -Bottom 0 -Right 0
        }

        # Drive chart
        $driveUsedGb = [math]::Round((($cDrive.Size - $cDrive.FreeSpace) / 1GB), 2)
        $driveFreeGb = [math]::Round((($cDrive.FreeSpace) / 1GB), 2)

        $driveData = @(
            (New-SpectreChartItem -Label Used -Value $driveUsedGb -Color yellow),
            (New-SpectreChartItem -Label Free -Value $driveFreeGb -Color green)
        )
        $cLabel = "Disk Usage C: (GB)" | Format-SpectrePadded -Padding 1

        # Memory chart (Win32_OperatingSystem memory values are in KB)
        $memUsedGb = [math]::Round(((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 1KB) / 1GB), 2)
        $memFreeGb = [math]::Round(((($os.FreePhysicalMemory) * 1KB) / 1GB), 2)

        $memData = @(
            (New-SpectreChartItem -Label Used -Value $memUsedGb -Color yellow),
            (New-SpectreChartItem -Label Free -Value $memFreeGb -Color green)
        )
        $memLabel = "Memory Usage (GB)" | Format-SpectrePadded -Padding 1

        $g1 = $cLabel, ($driveData | Format-SpectreBreakdownChart -Width 45) | Format-SpectreGrid
        $g2 = $memLabel, ($memData   | Format-SpectreBreakdownChart -Width 45) | Format-SpectreGrid

        $physPanel = ($g1, $g2 | Format-SpectreRows | Format-SpectreColumns) |
            Format-SpectrePanel -Color orange1 -Title "Physical Information :computer_disk:"

        $uptime = "{0:dd\.hh\:mm\:ss}" -f (New-TimeSpan -Start $os.LastBootUpTime -End (Get-Date))

        $hardware = if ($cs.SystemFamily) { $cs.SystemFamily } else { "$($cs.Manufacturer): $($cs.Model)" }
        $cap = Write-SpectreHost "[violet bold]$($os.Caption)`n$hardware`n$($os.OSArchitecture)[/]" -PassThru |
            Format-SpectrePadded -Padding 1

        # Top 5 Processes
        $procTable = $proc | Sort-Object WorkingSetSize -Descending |
            Select-Object -First 5 -Property `
                @{Name="ID";Expression={$_.ProcessID}},
                Name,
                @{Name="Runtime";Expression={
                    $start = $_.CreationDate
                    if ($start -isnot [datetime]) {
                        $start = [Management.ManagementDateTimeConverter]::ToDateTime($start)
                    }
                    "{0:dd\.hh\:mm\:ss}" -f (New-TimeSpan -Start $start -End (Get-Date))
                }},
                @{Name="WS(M)";Expression={[int32]($_.WorkingSetSize/1MB)}} |
            Format-SpectreTable -Title ":gear:  Top 5 Processes" -Color yellow2

        $runGrid = Format-SpectreGrid -Data @(
            @("Running Processes:", $proc.Count),
            @("Running Services :", $svc.Count),
            @("System Uptime    :", $uptime)
        ) | Format-SpectrePadded -Padding 0.85 |
            Format-SpectrePanel -Color Green1 -Title "  Run Information :wrench:  "

        $runInfo = @($cap, $runGrid, $procTable) |
            ForEach-Object { $_ | New-SpectreGridRow } |
            Format-SpectreGrid |
            Format-SpectrePanel -Border none

        $piItems = @($physPanel, $link)
        if ($logoImage) { $piItems += $logoImage }

        $pi = $piItems |
            ForEach-Object { $_ | New-SpectreGridRow } |
            Format-SpectreGrid

        # Output panel
        $panel = @($runInfo, $pi) | Format-SpectreColumns -Padding 1 |
            Format-SpectrePadded -Padding 0.5 |
            Format-SpectrePanel -Title " :information:  [italic aqua]$($targetName.ToUpper()): System Status[/]" -Color cyan1

        return $panel
    }
    finally {
        if ($cimSession) {
            $cimSession | Remove-CimSession
        }
    }
}

#endregion Public command
