$store = 'HKCU:\Software\XOSToolkit\StockValues'
$hwRoot = 'SOFTWARE\XOSToolkit\StockHardware'
$hklm = [Microsoft.Win32.Registry]::LocalMachine

function Test-RestoredMarker {
    try {
        $k = $hklm.OpenSubKey($hwRoot, $false)
        if (-not $k) { return $false }
        try {
            $m = $k.GetValue('RestoredToStock', $null)
            return (($m -is [string]) -and ($m -ceq 'Verified'))
        } finally { $k.Close() }
    } catch { return $false }
}

function Remove-RestoredMarker {
    try {
        $k = $hklm.OpenSubKey($hwRoot, $true)
        if ($k) {
            try {
                $k.DeleteValue('RestoredToStock', $false)
                $k.DeleteValue('RestoredToStockUtc', $false)
            } finally { $k.Close() }
        }
    } catch {}
}

$restoredToStock = Test-RestoredMarker
if (-not $restoredToStock) {
    if (Test-Path -LiteralPath $store) { Remove-RestoredMarker; exit 0 }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\XOSToolkit') { Remove-RestoredMarker; exit 0 }
}
if ((& powercfg.exe /list 2>$null | Out-String) -match '31693169-3169-3169-3169-316931693169') { Remove-RestoredMarker; exit 0 }
if (Test-Path -LiteralPath (Join-Path $env:windir 'imribiy.pow')) { Remove-RestoredMarker; exit 0 }
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
if (-not $restoredToStock) {
foreach ($root in $uninstallRoots) {
    foreach ($entry in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        if (([string]$entry.GetValue('DisplayName') -like 'XOS Toolkit*') -or ($entry.PSChildName -like '*XOS-TOOLKIT*')) { Remove-RestoredMarker; exit 0 }
    }
}
}

if ($restoredToStock) {
    try { $hklm.DeleteSubKeyTree($hwRoot, $false) } catch {}
    $left = $null
    try { $left = $hklm.OpenSubKey($hwRoot, $false) } catch {}
    if ($left) {
        $left.Close()
        Remove-RestoredMarker
        try {
            $stale = $hklm.CreateSubKey($hwRoot)
            if ($stale) { try { $stale.SetValue('CaptureStatus', 'Incomplete', [Microsoft.Win32.RegistryValueKind]::String) } finally { $stale.Close() } }
        } catch {}
        Write-Output 'Stock hardware re-capture skipped: the previous records could not be cleared'
        exit 0
    }
}

$values = @(
    @('Control Panel\Cursors', 'PenVisualization'),
    @('SOFTWARE\Microsoft\Input', 'IsInputAppPreloadEnabled')
)

if ((-not $restoredToStock) -or (-not (Test-Path -LiteralPath $store))) {
try {
    New-Item -Path $store -Force -ErrorAction Stop | Out-Null
    foreach ($v in $values) {
        $data = 'absent'
        $key = Get-Item -LiteralPath ('HKCU:\' + $v[0]) -ErrorAction SilentlyContinue
        if ($key -and ($key.GetValueNames() -contains $v[1])) {
            if ($key.GetValueKind($v[1]) -eq [Microsoft.Win32.RegistryValueKind]::DWord) {
                $data = ([int]$key.GetValue($v[1])).ToString([Globalization.CultureInfo]::InvariantCulture)
            } else {
                $data = 'other'
            }
        }
        New-ItemProperty -LiteralPath $store -Name ($v[0] + '\' + $v[1]) -Value $data -PropertyType String -Force -ErrorAction Stop | Out-Null
    }
} catch {
    Write-Output ('Stock value capture failed: ' + $_.Exception.Message)
}
}

$hw = 'SOFTWARE\XOSToolkit\StockHardware'
$nicValues = @(
    'EnablePME', '*DeviceSleepOnDisconnect', '*EEE', 'AdvancedEEE', '*SipsEnabled',
    'EnableAspm', 'ASPM', '*ModernStandbyWoLMagicPacket', '*SelectiveSuspend',
    'EnableGigaLite', 'GigaLite', '*WakeOnMagicPacket', '*WakeOnPattern',
    'AutoPowerSaveModeEnabled', 'EEELinkAdvertisement', 'EeePhyEnable',
    'EnableGreenEthernet', 'EnableModernStandby', 'PowerDownPll', 'PowerSavingMode',
    'ReduceSpeedOnPowerDown', 'S5WakeOnLan', 'SavePowerNowEnabled', 'ULPMode',
    'WakeOnLink', 'WakeOnSlot', 'WakeOnLinkChg', 'WakeOnLinkUp', 'WakeUpModeCap',
    '*NicAutoPowerSaver', 'PowerSaveEnable', 'EnablePowerManagement',
    'ForceWakeFromMagicPacketOnModernStandby', 'WakeFromS5', 'WakeOn',
    'EnableSavePowerNow', '*EnableDynamicPowerGating', 'DynamicPowerGating',
    'EnableD3ColdInS0', 'WakeFromPowerOff', 'LogLinkStateEvent',
    'PnPCapabilities', 'WakeOnMagicPacketFromS5', 'WolShutdownLinkSpeed'
)

function Get-Captured($key, $name) {
    $kind = $key.GetValueKind($name)
    $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::DWord) { return 'DWord:' + ([int]$value).ToString([Globalization.CultureInfo]::InvariantCulture) }
    if ($kind -eq [Microsoft.Win32.RegistryValueKind]::String) { return 'String:' + [string]$value }
    return 'other:' + $kind
}

function Save-Captured([string]$subKey, [string]$name, [string]$data) {
    $target = $hklm.CreateSubKey($hw + '\' + $subKey)
    if (-not $target) { throw ('Could not create stock record for ' + $name) }
    try {
        $target.SetValue($name, $data, [Microsoft.Win32.RegistryValueKind]::String)
        if (($target.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::String) -or ($target.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -cne $data)) { throw ('Stock record did not verify for ' + $name) }
    } finally { $target.Close() }
}

$script:hardwareCaptureFailures = 0
$ErrorActionPreference = 'Stop'
try {
    $hklm.CreateSubKey($hw).Close()

    $services = $hklm.OpenSubKey('SYSTEM\CurrentControlSet\Services')
    if (-not $services) { throw 'Could not read the Services registry key' }
    if ($services) {
        foreach ($name in $services.GetSubKeyNames()) {
            try {
                $serviceKey = $services.OpenSubKey($name)
                if (-not $serviceKey) { $script:hardwareCaptureFailures++; continue }
                try {
                    if ($serviceKey.GetSubKeyNames() -contains 'Parameters') {
                        $params = $serviceKey.OpenSubKey('Parameters')
                        if (-not $params) { $script:hardwareCaptureFailures++ }
                        else {
                            try { if ($params.GetValueNames() -contains 'DmaRemappingCompatible') { Save-Captured 'Dma' $name (Get-Captured $params 'DmaRemappingCompatible') } } finally { $params.Close() }
                        }
                    }
                } finally { $serviceKey.Close() }
            } catch { $script:hardwareCaptureFailures++ }
        }
        $services.Close()
    }

    $pci = $hklm.OpenSubKey('SYSTEM\CurrentControlSet\Enum\PCI')
    if (-not $pci) { throw 'Could not read the PCI registry key' }
    if ($pci) {
        foreach ($dev in $pci.GetSubKeyNames()) {
            try {
                $devKey = $pci.OpenSubKey($dev)
                if (-not $devKey) { $script:hardwareCaptureFailures++; continue }
                try {
                    foreach ($inst in $devKey.GetSubKeyNames()) {
                        try {
                            $instKey = $devKey.OpenSubKey($inst)
                            if (-not $instKey) { $script:hardwareCaptureFailures++; continue }
                            try {
                                if ($instKey.GetSubKeyNames() -contains 'Device Parameters') {
                                    $deviceKey = $instKey.OpenSubKey('Device Parameters')
                                    if (-not $deviceKey) { $script:hardwareCaptureFailures++ }
                                    else {
                                        try {
                                            if ($deviceKey.GetSubKeyNames() -contains 'Interrupt Management') {
                                                $interruptKey = $deviceKey.OpenSubKey('Interrupt Management')
                                                if (-not $interruptKey) { $script:hardwareCaptureFailures++ }
                                                else {
                                                    try {
                                                        if ($interruptKey.GetSubKeyNames() -contains 'MessageSignaledInterruptProperties') {
                                                            $msi = $interruptKey.OpenSubKey('MessageSignaledInterruptProperties')
                                                            if (-not $msi) { $script:hardwareCaptureFailures++ }
                                                            else {
                                                                try { if ($msi.GetValueNames() -contains 'MSISupported') { Save-Captured 'Msi' ('PCI\' + $dev + '\' + $inst) (Get-Captured $msi 'MSISupported') } } finally { $msi.Close() }
                                                            }
                                                        }
                                                    } finally { $interruptKey.Close() }
                                                }
                                            }
                                        } finally { $deviceKey.Close() }
                                    }
                                }
                            } finally { $instKey.Close() }
                        } catch { $script:hardwareCaptureFailures++ }
                    }
                } finally { $devKey.Close() }
            } catch { $script:hardwareCaptureFailures++ }
        }
        $pci.Close()
    }

    $class = $hklm.OpenSubKey('SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}')
    if (-not $class) { throw 'Could not read the network adapter class registry key' }
    if ($class) {
        foreach ($index in $class.GetSubKeyNames()) {
            if ($index -notmatch '^\d+$') { continue }
            try {
                $adapter = $class.OpenSubKey($index)
                if (-not $adapter) { $script:hardwareCaptureFailures++; continue }
                try {
                    $names = $adapter.GetValueNames()
                    $medium = [string]$adapter.GetValue('*PhysicalMediaType')
                    if (($names -contains '*SpeedDuplex') -and $medium -ne '9' -and $medium -ne '16') {
                        $id = [string]$adapter.GetValue('NetCfgInstanceId')
                        if ([string]::IsNullOrEmpty($id)) { $id = 'class-' + $index }
                        foreach ($name in $nicValues) {
                            if ($names -contains $name) { Save-Captured ('Nic\' + $id) $name (Get-Captured $adapter $name) }
                            elseif ($name -eq 'PnPCapabilities') { Save-Captured ('Nic\' + $id) $name 'Absent' }
                        }
                    }
                } finally { $adapter.Close() }
            } catch { $script:hardwareCaptureFailures++ }
        }
        $class.Close()
    }

    try {
        $searcher = New-Object System.Management.ManagementObjectSearcher('root\wmi', 'SELECT * FROM MSPower_DeviceEnable')
        try {
            foreach ($instance in $searcher.Get()) {
                try {
                    if ($instance['Enable'] -eq $true) {
                        $instanceName = [string]$instance['InstanceName']
                        $data = 'True'
                        try {
                            $driver = $null
                            $enumKey = $hklm.OpenSubKey('SYSTEM\CurrentControlSet\Enum\' + ($instanceName -replace '_\d+$', ''))
                            if ($enumKey) { try { $driver = [string]$enumKey.GetValue('Driver') } finally { $enumKey.Close() } }
                            if ($driver) {
                                $classKey = $hklm.OpenSubKey('SYSTEM\CurrentControlSet\Control\Class\' + $driver)
                                if ($classKey) {
                                    try {
                                        if ($classKey.GetValueNames() -contains 'PnPCapabilities') { $data = 'True|' + (Get-Captured $classKey 'PnPCapabilities') } else { $data = 'True|Absent' }
                                    } finally { $classKey.Close() }
                                }
                            }
                        } catch { $data = 'True' }
                        try { Save-Captured 'MsPower' $instanceName $data } catch { $script:hardwareCaptureFailures++ }
                    }
                } finally { $instance.Dispose() }
            }
        } finally { $searcher.Dispose() }
    } catch {}

    $done = $hklm.CreateSubKey($hw)
    try {
        $status = if ($script:hardwareCaptureFailures -eq 0) { 'Complete' } else { 'Incomplete:' + $script:hardwareCaptureFailures }
        $done.SetValue('CaptureStatus', $status, [Microsoft.Win32.RegistryValueKind]::String)
    } finally { $done.Close() }
} catch {
    try {
        $done = $hklm.CreateSubKey($hw)
        if ($done) { try { $done.SetValue('CaptureStatus', 'Incomplete', [Microsoft.Win32.RegistryValueKind]::String) } finally { $done.Close() } }
    } catch {}
    Write-Output ('Stock hardware capture failed: ' + $_.Exception.Message)
}
