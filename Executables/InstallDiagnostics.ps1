param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Start', 'Finish')]
    [string]$Phase
)

$logDirectory = Join-Path $env:ProgramData 'AME\Logs'
$logFile = Join-Path $logDirectory 'XOS-Install.log'
$sessionFile = Join-Path $logDirectory 'XOS-Install.session'
. (Join-Path $PSScriptRoot 'WebView2State.ps1')

try { New-Item -Path $logDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null }
catch { exit 0 }

function Write-Log {
    param([string]$Message)
    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        [System.IO.File]::AppendAllText($logFile, "[$timestamp] [$Phase] $Message`r`n", [System.Text.Encoding]::UTF8)
    } catch { }
}

function Get-PlaybookVersion {
    try {
        $root = Split-Path $PSScriptRoot -Parent
        $conf = Join-Path $root 'playbook.conf'
        if (Test-Path $conf) {
            [xml]$xml = Get-Content -LiteralPath $conf -Raw -ErrorAction Stop
            return [string]$xml.Playbook.Version
        }
    } catch { }
    return 'unknown'
}

function Get-RegistryValue {
    param([string]$Path, [string]$Name)
    try {
        $value = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
        if ($null -eq $value) { return 'not set' }
        return [string]$value
    } catch { return 'not present' }
}

function Write-HostFacts {
    $osPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $product = Get-RegistryValue $osPath 'ProductName'
    $edition = Get-RegistryValue $osPath 'EditionID'
    $display = Get-RegistryValue $osPath 'DisplayVersion'
    $build = Get-RegistryValue $osPath 'CurrentBuildNumber'
    $buildNumber = 0
    if ([int]::TryParse($build, [ref]$buildNumber) -and $buildNumber -ge 22000) {
        $product = $product -replace '^Windows 10', 'Windows 11'
    }
    $ubr = Get-RegistryValue $osPath 'UBR'
    $installType = Get-RegistryValue $osPath 'InstallationType'
    Write-Log "Windows=$product; DisplayVersion=$display; Edition=$edition; Build=$build.$ubr; InstallationType=$installType"
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $elevated = 'unknown'
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        $elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }
    Write-Log "Architecture=$([Environment]::Is64BitOperatingSystem); ProcessArchitecture=$env:PROCESSOR_ARCHITECTURE; PowerShell=$($PSVersionTable.PSVersion); Culture=$PSCulture; Elevated=$elevated; Identity=$($identity.User.Value)"

    try {
        $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        Write-Log "Hardware=$($system.Manufacturer) $($system.Model); MemoryBytes=$($system.TotalPhysicalMemory)"
    } catch { Write-Log "Hardware query failed: $($_.Exception.Message)" }

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        Write-Log "CPU=$($cpu.Name); Cores=$($cpu.NumberOfCores); LogicalProcessors=$($cpu.NumberOfLogicalProcessors)"
    } catch { Write-Log "CPU query failed: $($_.Exception.Message)" }
}

function Write-FeatureStates {
    $wanted = @(
        'DirectPlay',
        'Microsoft-Hyper-V-All',
        'Microsoft-Windows-Subsystem-Linux',
        'VirtualMachinePlatform',
        'HypervisorPlatform',
        'SMBDirect',
        'MSRDC-Infrastructure',
        'WorkFolders-Client'
    )

    try {
        $states = @{}
        Get-WindowsOptionalFeature -Online -ErrorAction Stop | ForEach-Object {
            $states[$_.FeatureName] = [string]$_.State
        }
        foreach ($name in $wanted) {
            $state = if ($states.ContainsKey($name)) { $states[$name] } else { 'not present' }
            Write-Log "Feature $name=$state"
        }
    } catch { Write-Log "Optional feature query failed: $($_.Exception.Message)" }

    try {
        $capability = Get-WindowsCapability -Online -Name 'App.StepsRecorder~~~~0.0.1.0' -ErrorAction Stop
        Write-Log "Capability App.StepsRecorder=$($capability.State)"
    } catch { Write-Log "Capability App.StepsRecorder=not present or query failed ($($_.Exception.Message))" }
}

function Write-ServiceStates {
    foreach ($service in @(
        'WinDefend', 'WdFilter', 'WdNisSvc', 'SecurityHealthService', 'wscsvc',
        'EventLog', 'BITS', 'wuauserv', 'DoSvc', 'WSearch', 'SysMain', 'DiagTrack',
        'edgeupdate', 'edgeupdatem'
    )) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$service"
        if (Test-Path -LiteralPath $path) {
            $start = Get-RegistryValue $path 'Start'
            $status = try { [string](Get-Service -Name $service -ErrorAction Stop).Status } catch { 'unavailable' }
            Write-Log "Service $service Start=$start; Status=$status"
        } else {
            Write-Log "Service $service=not present"
        }
    }
}

function Write-RemovalStates {
    $null = Write-WebView2State
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ([string]::IsNullOrWhiteSpace($programFilesX86)) { $programFilesX86 = $env:ProgramFiles }
    $paths = @(
        (Join-Path $env:ProgramFiles 'XOS Toolkit\XOS-Toolkit.exe'),
        (Join-Path $programFilesX86 'Microsoft\Edge\Application'),
        (Join-Path $programFilesX86 'Microsoft\EdgeWebView\Application'),
        (Join-Path $env:SystemRoot 'System32\smartscreen.exe'),
        (Join-Path $env:SystemRoot 'System32\smartscreen.old'),
        (Join-Path $env:SystemRoot 'service-backups\xos-default-services.reg')
    )
    foreach ($path in $paths) { Write-Log "Path $(if (Test-Path -LiteralPath $path) { 'present' } else { 'missing' }): $path" }

    try {
        $edgeTasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -like '*MicrosoftEdgeUpdate*' })
        Write-Log "Shared Edge/WebView2 updater scheduled tasks=$($edgeTasks.Count)"
        foreach ($task in $edgeTasks) { Write-Log "Edge updater task $($task.TaskPath)$($task.TaskName) State=$($task.State)" }
    } catch { Write-Log "Scheduled task query failed: $($_.Exception.Message)" }

    try {
        $blocked = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\XOS Toolkit\WebView2' -Name 'UpdaterBlocked' -ErrorAction SilentlyContinue).UpdaterBlocked
        Write-Log "Edge updater blocked marker=$blocked"
    } catch { Write-Log "Edge updater marker query failed: $($_.Exception.Message)" }

    $geoPath = 'Registry::HKEY_USERS\.DEFAULT\Control Panel\International\Geo'
    $savedMarkers = @('XOS_SavedNation', 'XOS_SavedNationExists', 'XOS_SavedGeoName', 'XOS_SavedGeoNameExists', 'XOS_SavedDeviceRegion', 'XOS_SavedDeviceRegionExists') |
        Where-Object { $null -ne (Get-ItemProperty -LiteralPath $geoPath -Name $_ -ErrorAction SilentlyContinue) }
    Write-Log "Edge region restore markers remaining=$($savedMarkers.Count)"
}

function Write-RebootState {
    $signals = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $signals += 'CBS' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $signals += 'WindowsUpdate' }
    try {
        $pending = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop).PendingFileRenameOperations
        if ($pending) { $signals += "PendingFileRenameOperations:$($pending.Count)" }
    } catch { }
    Write-Log "Pending reboot signals=$(if ($signals.Count -eq 0) { 'none' } else { $signals -join ',' })"

    try {
        $scheme = (& powercfg.exe /getactivescheme 2>&1 | Out-String).Trim()
        Write-Log "Active power scheme=$scheme"
    } catch { Write-Log "Active power scheme query failed: $($_.Exception.Message)" }
}

function Write-QuickState {
    foreach ($path in @(
        (Join-Path $env:SystemRoot 'service-backups\xos-default-services.reg')
    )) { Write-Log "Backup present=$([bool](Test-Path -LiteralPath $path)): $path" }

    Write-RebootState
}

try {
    $version = Get-PlaybookVersion
    if ($Phase -eq 'Start') {
        $session = [guid]::NewGuid().ToString('N')
        "$session|$(Get-Date -Format 'o')|$version" | Out-File -FilePath $sessionFile -Encoding ascii -Force
        Write-Log "=== XOS installation session started; Session=$session; Playbook=$version ==="
    } else {
        $session = if (Test-Path $sessionFile) { (Get-Content -LiteralPath $sessionFile -First 1) } else { 'unknown' }
        Write-Log "=== XOS installation final state; Session=$session; Playbook=$version ==="
    }

    Write-HostFacts
    if ($Phase -eq 'Finish') {
        Write-FeatureStates
        Write-ServiceStates
        Write-RemovalStates
        Write-RebootState
    }
    Write-Log "=== XOS installation diagnostics $($Phase.ToLowerInvariant()) complete ==="
} catch {
    Write-Log "Diagnostics failed: $($_.Exception.ToString())"
} finally {
    if ($Phase -eq 'Finish') { Remove-Item -LiteralPath $sessionFile -Force -ErrorAction SilentlyContinue }
}

exit 0
