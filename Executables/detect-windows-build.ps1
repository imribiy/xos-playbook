if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    exit 1
}

$script:BuildLog = Join-Path $env:ProgramData 'AME\Logs\XOS-Scripts.log'
function Write-BuildLog([string]$Message) {
    try {
        if (!(Test-Path (Split-Path $script:BuildLog -Parent))) {
            New-Item -Path (Split-Path $script:BuildLog -Parent) -ItemType Directory -Force | Out-Null
        }
        ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] detect-windows-build: ' + $Message) |
            Out-File -FilePath $script:BuildLog -Append -Encoding utf8
    } catch { }
}

$script:UserHivePattern = '^S-1-5-21-[0-9-]+$'

function Get-UserHiveRoots {
    $roots = New-Object System.Collections.ArrayList
    $users = $null
    try {
        $users = [Microsoft.Win32.Registry]::Users
        foreach ($name in $users.GetSubKeyNames()) {
            if ($name -match $script:UserHivePattern) {
                try { $null = $roots.Add($users.OpenSubKey($name, $true)) } catch { }
            }
        }
        if ($roots.Count -eq 0) {
            try { $null = $roots.Add($users.OpenSubKey('.DEFAULT', $true)) } catch { }
        }
    }
    catch {
        Write-BuildLog ("  could not enumerate user hives: " + $_.Exception.Message)
    }
    finally {
        if ($users) { $users.Close() }
    }
    return $roots
}

function Set-RegistryBatch {
    param (
        [string]$Path,
        [hashtable]$Properties,
        [string]$Hive = "HKCU"
    )

    $roots = @()
    if ($Hive.ToUpperInvariant() -eq 'HKLM') {
        $roots = @([Microsoft.Win32.Registry]::LocalMachine)
    }
    elseif ($Hive.ToUpperInvariant() -eq 'HKCU') {
        $roots = Get-UserHiveRoots
    }
    else {
        throw "Unsupported registry hive: $Hive"
    }

    $keyPath = $Path.TrimStart('\')
    $valueRights = [System.Security.AccessControl.RegistryRights]'SetValue, QueryValues'
    foreach ($root in $roots) {
        $key = $null
        try {
            try { $key = $root.OpenSubKey($keyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, $valueRights) } catch { $key = $null }
            if ($null -eq $key) { $key = $root.CreateSubKey($keyPath) }
            if ($null -eq $key) { throw "Could not open registry path" }
        }
        catch {
            $inner = $_.Exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            Write-BuildLog ("  FAILED $Hive`:$Path - the key could not be opened for writing: " + $inner.Message)
            if ($key) { $key.Close() }
            continue
        }
        try {
            foreach ($name in $Properties.Keys) {
                $data = $Properties[$name]
                $value = $data
                $type = "DWord"
                if ($data -is [Array] -and $data.Count -eq 2 -and $data[1] -in @("String","DWord","Binary","ExpandString","MultiString","QWord")) {
                    $value = $data[0]
                    $type = $data[1]
                }
                elseif ($data -is [byte[]]) {
                    $type = "Binary"
                }
                elseif ($data -is [String]) {
                    $type = "String"
                }
                $propertyName = if ($name -eq '(Default)') { '' } else { [string]$name }
                try {
                    $key.SetValue($propertyName, $value, [Microsoft.Win32.RegistryValueKind]$type)
                }
                catch {
                    $inner = $_.Exception
                    while ($inner.InnerException) { $inner = $inner.InnerException }
                    if ($inner -is [System.UnauthorizedAccessException]) {
                        Write-BuildLog ("  SKIPPED $Hive`:$Path $name - the key opened for writing but Windows refused this value (access denied), so it is left as it is: " + $inner.Message)
                    }
                    else {
                        Write-BuildLog ("  FAILED $Hive`:$Path $name - " + $inner.Message)
                    }
                }
            }
        }
        catch {
            Write-BuildLog ("  FAILED $Hive`:$Path $name - " + $_.Exception.Message)
        }
        finally {
            $key.Close()
        }
    }

    if ($roots.Count -eq 0) {
        Write-BuildLog "  FAILED $Hive`:$Path - no user hive was found"
    }
}

$script:FeedsPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds'
$script:FeedsValue = 'ShellFeedsTaskbarViewMode'

function Test-FeedsTaskbarViewMode {
    foreach ($hive in Get-UserHiveRoots) {
        try {
            $key = $hive.OpenSubKey($script:FeedsPath)
            if ($null -eq $key) { continue }
            try {
                $value = $key.GetValue($script:FeedsValue)
                if ($null -ne $value -and [int]$value -eq 2) { return $true }
            }
            finally { $key.Close() }
        } catch { }
    }
    return $false
}

function Set-FeedsTaskbarViewMode {
    if (Test-FeedsTaskbarViewMode) { return }

    $written = 0
    $denied = $false
    $errors = New-Object System.Collections.ArrayList
    foreach ($hive in Get-UserHiveRoots) {
        $key = $null
        try {
            $key = $hive.OpenSubKey($script:FeedsPath, $true)
            if ($null -eq $key) { $key = $hive.CreateSubKey($script:FeedsPath) }
            if ($null -eq $key) { throw "Could not open $script:FeedsPath" }
            $key.SetValue($script:FeedsValue, 2, [Microsoft.Win32.RegistryValueKind]::DWord)
            $written++
        } catch {
            $inner = $_.Exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            if ($inner -is [System.UnauthorizedAccessException]) { $denied = $true }
            $null = $errors.Add($_.Exception.Message)
        }
        finally {
            if ($key) { $key.Close() }
        }
    }

    if (Test-FeedsTaskbarViewMode) {
        Write-BuildLog ("  Feeds setting applied to $written user hive(s)")
        return
    }
    $policy = $null
    try { $policy = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' -Name 'EnableFeeds' -ErrorAction Stop } catch { }
    $reason = ($errors | Select-Object -Unique) -join '; '
    if ($null -ne $policy -and [int]$policy -eq 0) {
        Write-BuildLog ("  SKIPPED ShellFeedsTaskbarViewMode ($reason); News and interests is off through the EnableFeeds policy")
        return
    }
    foreach ($message in ($errors | Select-Object -Unique)) { Write-BuildLog ("  Feeds write failed: " + $message) }
    $version = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $staged = Join-Path ([Environment]::GetFolderPath('Startup')) 'feeds-home.bat'
    $ucpdRunning = $false
    try { $ucpdRunning = (Get-Service -Name 'UCPD' -ErrorAction Stop).Status -eq 'Running' } catch { }
    $ucpdStart = $null
    try { $ucpdStart = [int](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\UCPD' -Name 'Start' -ErrorAction Stop).Start } catch { }
    if ($denied -and "$($version.EditionID)" -like 'Core*' -and (Test-Path -LiteralPath $staged) -and $ucpdRunning -and $ucpdStart -eq 4) {
        Write-BuildLog '  DEFERRED ShellFeedsTaskbarViewMode: Windows Home has no policy route, and the UCPD driver is still running in this boot while its service reads Start 4, so the staged logon step writes it at a later sign-in'
        return
    }
    Write-BuildLog '  FAILED ShellFeedsTaskbarViewMode did not verify as 2 in any user hive and the EnableFeeds policy is not set'
}
$currentBuild = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
$isWin11 = $currentBuild -ge 22000
$isServer = $false
$serverCheckValues = @("CompositionEditionID", "EditionID", "InstallationType", "ProductName", "SoftwareType", "System")
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

foreach ($value in $serverCheckValues) {
    try {
        $regValue = Get-ItemPropertyValue -Path $regPath -Name $value -ErrorAction SilentlyContinue
        if ($regValue -and $regValue.ToString().ToLower().Contains("server")) {
            $isServer = $true
            break
        }
    } catch {
        continue
    }
}

if ($isServer) {
    Write-BuildLog "branch: SERVER on build $currentBuild"
    Set-RegistryBatch -Hive "HKLM" -Path "\Software\Policies\Microsoft\Windows\Server\InitialConfigurationTasks" -Properties @{
        "DoNotOpenAtLogon" = 1
    }
    try {
        Disable-ScheduledTask -TaskName "ServerManager" -TaskPath "\Microsoft\Windows\Server Manager\" -ErrorAction Stop
    } catch {
        Write-BuildLog "  Could not disable Server Manager task: $_"
    }
    try {
        $trkService = Get-Service -Name "MSDTC" -ErrorAction SilentlyContinue
        if ($trkService) {
            if ($trkService.Status -eq "Running") {
                Stop-Service -Name "MSDTC" -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name "MSDTC" -StartupType Disabled -ErrorAction SilentlyContinue
        }
    } catch {
        Write-BuildLog "  Could not disable MSDTC service: $_"
    }
    $azureArcPath = Join-Path $env:SystemRoot 'AzureArcSetup\Systray'
    if (Test-Path $azureArcPath) {
        try {
            $uninstaller = Get-ChildItem -Path $azureArcPath -Filter "*.exe" -Recurse | 
                          Where-Object { $_.Name -match "uninstall|remove" -or $_.FullName -match "uninstall" } |
                          Select-Object -First 1
            
            if ($uninstaller) {
                Start-Process -FilePath $uninstaller.FullName -ArgumentList "/quiet /norestart" -Wait -NoNewWindow
            }
            $runRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            if (Test-Path $runRegPath) {
                $azureRunValue = Get-ItemProperty -Path $runRegPath -Name "AzureArcSetup" -ErrorAction SilentlyContinue
                if ($azureRunValue) {
                    Remove-ItemProperty -Path $runRegPath -Name "AzureArcSetup" -Force -ErrorAction SilentlyContinue
                }
            }
            Start-Sleep -Seconds 2
            Remove-Item -Path $azureArcPath -Recurse -Force -ErrorAction SilentlyContinue
            $azureArcTask = Get-ScheduledTask -TaskName "*Azure*Arc*" -ErrorAction SilentlyContinue
            if ($azureArcTask) {
                Unregister-ScheduledTask -TaskName $azureArcTask.TaskName -Confirm:$false -ErrorAction SilentlyContinue
            }
            
        } catch {
            Write-BuildLog "  Could not fully remove Azure Arc Setup: $_"
        }
    } else {
        try {
            $runRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            if (Test-Path $runRegPath) {
                $azureRunValue = Get-ItemProperty -Path $runRegPath -Name "AzureArcSetup" -ErrorAction SilentlyContinue
                if ($azureRunValue) {
                    Remove-ItemProperty -Path $runRegPath -Name "AzureArcSetup" -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-BuildLog "  Could not remove AzureArcSetup registry entry: $_"
        }
    }
    
}

Set-RegistryBatch -Path "\Control Panel\Desktop" -Properties @{
    "DragFullWindows"     = @("0", "String")
    "UserPreferencesMask" = @([byte[]](0x90, 0x12, 0x03, 0x80, 0x12, 0x00, 0x00, 0x00), "Binary")
}

Set-RegistryBatch -Path "\Control Panel\Desktop\WindowMetrics" -Properties @{
    "MinAnimate" = @("0", "String")
}

Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Properties @{
    "ListviewAlphaSelect" = 0
    "ListviewShadow"      = 0
    "TaskbarAnimations"   = 0
}

Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Properties @{
    "VisualFXSetting" = 3
}

Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Properties @{
    "SystemUsesLightTheme" = 0
    "AppsUseLightTheme"    = 0
}

Set-RegistryBatch -Path "\Software\Microsoft\Windows\DWM" -Properties @{
    "EnableAeroPeek" = 0
}

Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\PenWorkspace" -Properties @{
    "PenWorkspaceButtonDesiredVisibility" = 0
}

if ($isWin11) {
    Write-BuildLog "branch: WINDOWS 11 on build $currentBuild"
    Set-RegistryBatch -Path "\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Properties @{ "(Default)" = @("", "String") }
    Set-RegistryBatch -Path "\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Properties @{ "(Default)" = @("", "String") }

    Set-RegistryBatch -Path "\Software\Microsoft\DirectX\UserGpuPreferences" -Properties @{
        "DirectXUserGlobalSettings" = @("SwapEffectUpgradeEnable=1;VRROptimizeEnable=0;", "String")
    }
    Set-RegistryBatch -Hive "HKLM" -Path "\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Properties @{
        "HwSchMode" = 2
    }

    Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Properties @{
        "TaskbarAl"          = 0
        "ShowTaskViewButton" = 0
    }

    Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\Search" -Properties @{
        "SearchboxTaskbarMode" = 1
    }

    Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Properties @{ "EnableTransparency" = 0 }
    Set-RegistryBatch -Path "\Software\Microsoft\Windows\DWM" -Properties @{ "AlwaysHibernateThumbnails" = 0 }

    if ($currentBuild -ge 22631) {
        Write-BuildLog "  nested: build $currentBuild >= 22631, enabling Taskbar End Task"
        Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Properties @{
            "TaskbarEndTask" = 1
        }
    }

    Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration" -Properties @{
        "IsResumeAllowed" = 0
    }

    if (-not $isServer -and !(Get-Process explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer
    }

} else {
    Write-BuildLog "branch: WINDOWS 10 on build $currentBuild"
    if ($currentBuild -ge 18362) {
        Write-BuildLog "  nested: build $currentBuild >= 18362, applying VRR setting"
        Set-RegistryBatch -Path "\Software\Microsoft\DirectX\UserGpuPreferences" -Properties @{
            "DirectXUserGlobalSettings" = @("VRROptimizeEnable=0;", "String")
        }
    }

    Set-RegistryBatch -Path "\SOFTWARE\Microsoft\TabletTip\1.7" -Properties @{ "TipbandDesiredVisibility" = 0 }
    Set-RegistryBatch -Path "\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Properties @{ "PeopleBand" = 0 }
    Set-FeedsTaskbarViewMode

    Set-RegistryBatch -Path "\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Properties @{ "HideSCAMeetNow" = 1 }
    Set-RegistryBatch -Hive "HKLM" -Path "\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Properties @{ "HideSCAMeetNow" = 1 }

    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Force -ErrorAction SilentlyContinue
}

