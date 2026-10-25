param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("PrepareRuntime", "SpoofRegion", "Browser", "Runtime", "RestoreRegion", "BlockUpdater")]
    [string]$Action
)

$EdgeUninstallRoots = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
$EdgeUpdateRoots = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate')
$EdgeUpdateDevRoots = @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev')
if (-not [Environment]::Is64BitOperatingSystem) {
    $EdgeUninstallRoots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    $EdgeUpdateRoots = @('HKLM:\SOFTWARE\Microsoft\EdgeUpdate')
    $EdgeUpdateDevRoots = @('HKLM:\SOFTWARE\Microsoft\EdgeUpdateDev')
} else {
    $EdgeUninstallRoots += 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $EdgeUpdateRoots += 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
    $EdgeUpdateDevRoots += 'HKLM:\SOFTWARE\Microsoft\EdgeUpdateDev'
}

$Components = @{
    Browser = @{
        Guid         = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
        UninstallKeys = @($EdgeUninstallRoots | ForEach-Object { Join-Path $_ 'Microsoft Edge' })
        Shortcuts    = @(
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"
            "$env:PUBLIC\Desktop\Microsoft Edge.lnk"
            "$env:USERPROFILE\Desktop\Microsoft Edge.lnk"
        )
        EnableDevPolicy = $true
    }
    Runtime = @{
        Guid         = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
        UninstallKeys = @($EdgeUninstallRoots | ForEach-Object { Join-Path $_ 'Microsoft EdgeWebView' })
        Shortcuts    = @()
        EnableDevPolicy = $true
    }
}

$GeoKey        = 'HKEY_USERS\.DEFAULT\Control Panel\International\Geo'
$DeviceRegionKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion'
$RegionKey     = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion'
$TemporaryRegion = 94
$TemporaryRegionName = 'DE'
$LogDirectory = Join-Path $env:ProgramData 'AME\Logs'
$LogFile = Join-Path $LogDirectory 'RemoveEdge.log'
$RuntimeStateKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\XOS Toolkit\WebView2'
$UpdaterTaskPrefixes = @(
    'MicrosoftEdgeUpdateTaskMachineCore'
    'MicrosoftEdgeUpdateTaskMachineUA'
)
$runtimePreserved = $false
. (Join-Path $PSScriptRoot 'WebView2State.ps1')

try { New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null } catch { }
function Write-Log {
    param([string]$Message)
    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        "[$timestamp] [PID:$PID] [$Action] $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
    } catch { }
}

function Add-UninstallSwitch {
    param(
        [AllowNull()][string]$Arguments,
        [Parameter(Mandatory = $true)][string]$Switch
    )
    if ([string]::IsNullOrWhiteSpace($Arguments)) { return $Switch }
    $pattern = '(?i)(^|\s)' + [regex]::Escape($Switch) + '(\s|$)'
    if ($Arguments -match $pattern) { return $Arguments }
    return $Arguments.TrimEnd() + ' ' + $Switch
}

function Get-EdgeClientStatePath {
    param([Parameter(Mandatory = $true)][string]$Guid)
    foreach ($root in $EdgeUpdateRoots) {
        $candidate = "$root\ClientState\$Guid"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return "$($EdgeUpdateRoots[0])\ClientState\$Guid"
}

function Stop-EdgeRemovalInfrastructure {
    foreach ($serviceName in @('edgeupdate', 'edgeupdatem')) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                Write-Log "Stopping updater service before removal: $serviceName"
                try { Run-AsTrustedInstaller ('sc.exe stop "' + $serviceName + '"') } catch { }
                try { $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15)) } catch { }
            }
        } catch {
            Write-Log "Could not stop updater service $serviceName`: $($_.Exception.Message)"
        }
    }

    $removalProcesses = @(
        'msedge', 'msedgewebview2', 'MicrosoftEdgeUpdate', 'RuntimeBroker',
        'SearchHost', 'SearchApp', 'SearchUI', 'StartMenuExperienceHost',
        'ShellExperienceHost', 'TextInputHost', 'backgroundTaskHost', 'Widgets'
    )
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        foreach ($processName in $removalProcesses) {
            Get-Process -Name $processName -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 300
        $running = @(
            Get-Process -Name $removalProcesses -ErrorAction SilentlyContinue
        )
        if ($running.Count -eq 0) { break }
    }
}

function Get-UpdaterTaskPaths {
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskName -like ($UpdaterTaskPrefixes[0] + '*') -or
            $_.TaskName -like ($UpdaterTaskPrefixes[1] + '*')
        })
        foreach ($task in $tasks) { "$($task.TaskPath)$($task.TaskName)" }
    } catch {
        Write-Log "Could not enumerate Edge Update tasks: $($_.Exception.Message)"
    }
}

$script:UpdaterTaskRunState = $null

function Get-UpdaterTaskState {
    param([Parameter(Mandatory = $true)][string]$TaskPath)
    $script:UpdaterTaskRunState = $null
    $scheduler = $null
    try {
        $taskName = Split-Path -Path $TaskPath -Leaf
        $taskFolder = Split-Path -Path $TaskPath -Parent
        if ([string]::IsNullOrWhiteSpace($taskFolder)) { $taskFolder = '\' }
        $scheduler = New-Object -ComObject 'Schedule.Service'
        $scheduler.Connect()
        $task = $scheduler.GetFolder($taskFolder).GetTask($taskName)
        $runStates = @('Unknown', 'Disabled', 'Queued', 'Ready', 'Running')
        $runState = [int]$task.State
        $script:UpdaterTaskRunState = if ($runState -ge 0 -and $runState -lt $runStates.Count) { $runStates[$runState] } else { "$runState" }
        if ([bool]$task.Enabled) { return 1 }
        return 0
    } catch {
        $exception = $_.Exception
        while ($exception) {
            if ($exception.HResult -eq 0x80070002 -or $exception.HResult -eq 0x80070003) { return $null }
            $exception = $exception.InnerException
        }
        Write-Log "Could not read updater task state $TaskPath`: $($_.Exception.Message)"
        return -1
    } finally {
        if ($scheduler) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($scheduler) } catch { } }
    }
}

function Read-UpdaterTaskStateSettled {
    param([Parameter(Mandatory = $true)][string]$TaskPath)
    $state = Get-UpdaterTaskState $TaskPath
    for ($read = 1; $read -lt 4 -and $null -ne $state -and $state -ne 0; $read++) {
        Start-Sleep -Milliseconds 500
        $state = Get-UpdaterTaskState $TaskPath
    }
    return $state
}

function Save-UpdaterState {
    if ([int][Microsoft.Win32.Registry]::GetValue($RuntimeStateKey, 'UpdaterStateSaved', 0) -eq 1) { return }

    $state = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\XOS Toolkit\WebView2')
    if (-not $state) { throw 'The previous Edge Update state could not be saved.' }
    try {
        foreach ($serviceName in @('edgeupdate', 'edgeupdatem')) {
            $start = [Microsoft.Win32.Registry]::GetValue(
                "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$serviceName", 'Start', $null)
            if ($null -ne $start) {
                $state.SetValue("UpdaterService_${serviceName}_Start", [int]$start, [Microsoft.Win32.RegistryValueKind]::DWord)
            }
        }
        $taskPaths = @(Get-UpdaterTaskPaths)
        foreach ($taskPath in $taskPaths) {
            $taskState = Get-UpdaterTaskState $taskPath
            if ($null -ne $taskState -and $taskState -ge 0) {
                $taskName = Split-Path -Path $taskPath -Leaf
                $state.SetValue("UpdaterTask_$taskName", [int]$taskState, [Microsoft.Win32.RegistryValueKind]::DWord)
            }
        }
        if ($taskPaths.Count -gt 0) {
            $state.SetValue('UpdaterTaskPaths', ($taskPaths -join "`n"), [Microsoft.Win32.RegistryValueKind]::String)
        }
        $state.SetValue('UpdaterStateSaved', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
    } finally {
        $state.Close()
    }
    Write-Log 'Saved the previous Edge Update service and task states.'
}

function Block-EdgeUpdater {
    Save-UpdaterState
    $failures = New-Object System.Collections.Generic.List[string]
    Stop-EdgeRemovalInfrastructure

    foreach ($serviceName in @('edgeupdate', 'edgeupdatem')) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) { continue }
        try {
            if ($service.Status -eq 'Running') {
                try { Run-AsTrustedInstaller ('sc.exe stop "' + $serviceName + '"') } catch { }
                try { $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15)) } catch { }
                $service.Refresh()
            }
            if ($service.Status -eq 'Running') { [void]$failures.Add("$serviceName could not be stopped") }
            try { Run-AsTrustedInstaller ('sc.exe config "' + $serviceName + '" start= disabled') } catch { }
            $start = [Microsoft.Win32.Registry]::GetValue(
                "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$serviceName", 'Start', $null)
            if ($null -ne $start -and [int]$start -ne 4) { [void]$failures.Add("$serviceName could not be disabled") }
            else { Write-Log "Edge Update service disabled: $serviceName" }
        } catch {
            [void]$failures.Add("$serviceName`: $($_.Exception.Message)")
        }
    }

    $taskPaths = @(Get-UpdaterTaskPaths)
    foreach ($taskPath in $taskPaths) {
        $state = Get-UpdaterTaskState $taskPath
        if ($null -eq $state) { continue }
        $verify = $state
        $changeError = $null
        for ($attempt = 1; $attempt -le 3 -and $null -ne $verify -and $verify -ne 0; $attempt++) {
            try {
                Run-AsTrustedInstaller ('schtasks.exe /change /tn "' + $taskPath + '" /disable')
                $changeError = $null
            } catch {
                $changeError = $_.Exception.Message
            }
            $verify = Read-UpdaterTaskStateSettled $taskPath
            if ($null -ne $verify -and $verify -ne 0 -and $attempt -lt 3) {
                $readBack = if ($verify -eq 1) { 'still reads enabled' } else { 'could not be read back' }
                Write-Log "Edge Update task $taskPath $readBack after attempt $attempt (Task Scheduler run state: $script:UpdaterTaskRunState); stopping the updater and retrying."
                Stop-EdgeRemovalInfrastructure
                Start-Sleep -Seconds 1
            }
        }
        if ($verify -eq 0) {
            $detail = if ($script:UpdaterTaskRunState -and $script:UpdaterTaskRunState -ne 'Disabled') { " (Task Scheduler run state: $script:UpdaterTaskRunState)" } else { '' }
            Write-Log "Edge Update task disabled: $taskPath$detail"
        } elseif ($null -eq $verify) {
            Write-Log "Edge Update task is no longer present: $taskPath"
        } elseif ($verify -eq 1) {
            $reason = if ($changeError) { "$taskPath could not be disabled: $changeError" } else { "$taskPath could not be disabled" }
            [void]$failures.Add($reason)
        } elseif ($changeError) {
            [void]$failures.Add("$taskPath`: $changeError")
        } else {
            Write-Log "Edge Update task disable was sent but its state could not be read back: $taskPath"
        }
    }

    Stop-EdgeRemovalInfrastructure
    if ($failures.Count -gt 0) {
        Write-Log ('Edge Update blocking failed: ' + ($failures -join '; '))
        throw ('The shared Edge Update infrastructure could not be fully blocked. ' + ($failures -join '; '))
    }

    [Microsoft.Win32.Registry]::SetValue($RuntimeStateKey, 'UpdaterBlocked', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
    Write-Log 'Edge Update services and scheduled tasks are blocked because Edge is absent.'
}

function Get-WebView2ApplicationDirectories {
    param([object[]]$Executables)
    foreach ($file in $Executables) {
        try {
            $versionDirectory = Split-Path -Path $file -Parent
            $applicationDirectory = Split-Path -Path $versionDirectory -Parent
            if ($applicationDirectory -and $applicationDirectory -match '\\Microsoft\\EdgeWebView\\Application$') {
                $applicationDirectory
            }
        } catch { }
    }
}

function Remove-WebView2Registration {
    $guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$guid",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\ClientState\$guid",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\ClientStateMedium\$guid",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$guid",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientState\$guid",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientStateMedium\$guid",
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView'
    )
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Log "Removed WebView2 registration: $path"
        } catch {
            Write-Log "WebView2 registration cleanup failed for $path`: $($_.Exception.Message)"
        }
    }
}

function Invoke-WebView2Fallback {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Stop-EdgeRemovalInfrastructure
        $files = @(Get-WebView2Executables)
        if ($files.Count -eq 0) {
            Remove-WebView2Registration
            return $true
        }

        foreach ($directory in @(Get-WebView2ApplicationDirectories $files | Select-Object -Unique)) {
            Write-Log "Removing residual runtime directory: $directory"
            try {
                Run-AsTrustedInstaller ('cmd.exe /c rd /s /q "' + $directory + '"')
            } catch {
                Write-Log "TrustedInstaller residual cleanup failed for $directory`: $($_.Exception.Message)"
                try { Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction Stop } catch {
                    Write-Log "Direct residual cleanup failed for $directory`: $($_.Exception.Message)"
                }
            }
        }

        if (@(Get-WebView2Executables).Count -eq 0) {
            Remove-WebView2Registration
            Write-Log 'Residual WebView2 cleanup verified.'
            return $true
        }
        if ($attempt -lt 3) { Start-Sleep -Seconds 1 }
    }

    Write-Log ('Residual WebView2 cleanup could not remove: ' +
        (@(Get-WebView2Executables) -join '; '))
    return $false
}

function Run-AsTrustedInstaller {
    param([string]$Command)
    $ti = Join-Path $PSScriptRoot "MinSudo.exe"
    if (-not (Test-Path $ti)) { throw "MinSudo.exe was not found at $ti" }
    Write-Log "TrustedInstaller command: $Command"
    $process = Start-Process $ti -ArgumentList "--TrustedInstaller --NoLogo $Command" -Wait -WindowStyle Hidden -PassThru
    Write-Log "TrustedInstaller exit code: $($process.ExitCode)"
    if ($process.ExitCode -ne 0) { throw "TrustedInstaller command failed with exit code $($process.ExitCode): $Command" }
}

function ConvertTo-PowerShellLiteral {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return "''" }
    return "'" + ($Value -replace "'", "''") + "'"
}

function Invoke-AsTrustedInstallerOutput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [int]$TimeoutMs = 30000
    )
    $ti = Join-Path $PSScriptRoot 'MinSudo.exe'
    if (-not (Test-Path -LiteralPath $ti)) { throw "MinSudo.exe was not found at $ti" }

    $windowsRoot = [Environment]::GetFolderPath('Windows')
    $tempDirectory = Join-Path $windowsRoot 'Temp'
    if (-not (Test-Path -LiteralPath $tempDirectory)) {
        New-Item -ItemType Directory -Path $tempDirectory -Force -ErrorAction Stop | Out-Null
    }
    $token = 'XOS-TI-' + [Guid]::NewGuid().ToString('N')
    $wrapperPath = Join-Path $tempDirectory ($token + '.ps1')
    $outputPath = Join-Path $tempDirectory ($token + '.out')
    $exitCodePath = Join-Path $tempDirectory ($token + '.exit')
    $launcher = $null
    try {
        $wrapper = @'
$ErrorActionPreference = 'Stop'
$code = -1
$combined = ''
$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = __FILE_PATH__
    $psi.Arguments = __ARGUMENTS__
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $psi
    if (-not $child.Start()) { throw 'The child process could not be started.' }
    $outTask = $child.StandardOutput.ReadToEndAsync()
    $errTask = $child.StandardError.ReadToEndAsync()
    $child.WaitForExit()
    $stdout = $outTask.GetAwaiter().GetResult()
    $stderr = $errTask.GetAwaiter().GetResult()
    if ($stdout -and $stderr) { $combined = $stdout + ' | STDERR: ' + $stderr }
    elseif ($stderr) { $combined = $stderr }
    else { $combined = $stdout }
    $code = $child.ExitCode
} catch {
    $combined = $_.Exception.Message
}
[System.IO.File]::WriteAllText(__OUTPUT_PATH__, $combined, $utf8)
[System.IO.File]::WriteAllText(__EXIT_PATH__, [string]$code, $utf8)
exit $code
'@
        $wrapper = $wrapper.Replace('__FILE_PATH__', (ConvertTo-PowerShellLiteral $FilePath))
        $wrapper = $wrapper.Replace('__ARGUMENTS__', (ConvertTo-PowerShellLiteral $Arguments))
        $wrapper = $wrapper.Replace('__OUTPUT_PATH__', (ConvertTo-PowerShellLiteral $outputPath))
        $wrapper = $wrapper.Replace('__EXIT_PATH__', (ConvertTo-PowerShellLiteral $exitCodePath))
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($wrapperPath, $wrapper, $utf8)

        $launcherInfo = New-Object System.Diagnostics.ProcessStartInfo
        $launcherInfo.FileName = $ti
        $launcherInfo.Arguments = '-TI -P powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $wrapperPath + '"'
        $launcherInfo.UseShellExecute = $false
        $launcherInfo.CreateNoWindow = $true
        $launcherInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $launcherInfo.RedirectStandardOutput = $true
        $launcherInfo.RedirectStandardError = $true
        $launcher = New-Object System.Diagnostics.Process
        $launcher.StartInfo = $launcherInfo
        Write-Log "TrustedInstaller command with result capture: $FilePath $Arguments"
        if (-not $launcher.Start()) { throw 'TrustedInstaller launcher could not be started.' }
        $stdoutTask = $launcher.StandardOutput.ReadToEndAsync()
        $stderrTask = $launcher.StandardError.ReadToEndAsync()
        if (-not $launcher.WaitForExit($TimeoutMs)) {
            try { & (Join-Path $windowsRoot 'System32\taskkill.exe') /pid $launcher.Id /t /f > $null 2>&1 } catch { }
            throw "TrustedInstaller command timed out after $TimeoutMs ms."
        }
        $launcherStdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $launcherStderr = $stderrTask.GetAwaiter().GetResult().Trim()
        $launcherOutput = if ($launcherStdout -and $launcherStderr) {
            $launcherStdout + ' | STDERR: ' + $launcherStderr
        } elseif ($launcherStderr) {
            $launcherStderr
        } else {
            $launcherStdout
        }
        for ($i = 0; $i -lt 50 -and -not (Test-Path -LiteralPath $exitCodePath); $i++) {
            Start-Sleep -Milliseconds 100
        }
        if (-not (Test-Path -LiteralPath $exitCodePath)) {
            $message = "TrustedInstaller did not return the child result (launcher exit $($launcher.ExitCode)). $launcherOutput"
            throw $message.Trim()
        }
        $childExitCode = -1
        $exitText = [System.IO.File]::ReadAllText($exitCodePath).Trim()
        if (-not [int]::TryParse($exitText, [ref]$childExitCode)) {
            throw "TrustedInstaller returned an invalid child exit code: $exitText"
        }
        $childOutput = if (Test-Path -LiteralPath $outputPath) {
            [System.IO.File]::ReadAllText($outputPath).Trim()
        } else { '' }
        Write-Log "TrustedInstaller child exit code: $childExitCode (launcher exit $($launcher.ExitCode))"
        if (-not [string]::IsNullOrWhiteSpace($childOutput)) {
            Write-Log "TrustedInstaller child output: $childOutput"
        }
        return [pscustomobject]@{
            ExitCode = $childExitCode
            Output = $childOutput
            LauncherExitCode = $launcher.ExitCode
        }
    } finally {
        if ($launcher) { $launcher.Dispose() }
        Remove-Item -LiteralPath $wrapperPath, $outputPath, $exitCodePath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-DeviceRegionReg {
    param([string]$Arguments)
    $windowsRoot = [Environment]::GetFolderPath('Windows')
    $source = Join-Path $windowsRoot 'System32\reg.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $source = Join-Path $windowsRoot 'Sysnative\reg.exe'
    }
    if (-not (Test-Path -LiteralPath $source)) { throw "Registry helper was not found at $source" }
    $tempDirectory = Join-Path $windowsRoot 'Temp'
    if (-not (Test-Path -LiteralPath $tempDirectory)) {
        New-Item -ItemType Directory -Path $tempDirectory -Force -ErrorAction Stop | Out-Null
    }
    $temporaryHelper = Join-Path $tempDirectory ('XOS-Region-' + [Guid]::NewGuid().ToString('N') + '.exe')
    try {
        Copy-Item -LiteralPath $source -Destination $temporaryHelper -Force -ErrorAction Stop
        Write-Log "Using neutral-named registry helper for DeviceRegion: $temporaryHelper"
        $result = Invoke-AsTrustedInstallerOutput -FilePath $temporaryHelper -Arguments $Arguments
        if ($result.ExitCode -ne 0) {
            $details = if ([string]::IsNullOrWhiteSpace($result.Output)) { 'no child output' } else { $result.Output }
            throw "TrustedInstaller registry command failed with child exit code $($result.ExitCode): $details"
        }
    } finally {
        Remove-Item -LiteralPath $temporaryHelper -Force -ErrorAction SilentlyContinue
    }
}

Write-Log 'Action started'
try {
switch ($Action) {

    "PrepareRuntime" {
        $manufacturer = [Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation', 'Manufacturer', '')
        if ($manufacturer -eq 'XOS') {
            [Microsoft.Win32.Registry]::SetValue($RuntimeStateKey, 'PreserveRuntime', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            Write-Log 'Existing XOS installation: preserve any runtime restored by apps or the user.'
        }
    }

    "SpoofRegion" {
        $priorGeo = [Microsoft.Win32.Registry]::Users.OpenSubKey('.DEFAULT\Control Panel\International\Geo', $false)
        if (-not $priorGeo) {
            throw 'The default-user region key could not be opened, so the original region cannot be saved. Refusing to spoof it.'
        }
        try {
            $hasPendingSave = $null -ne $priorGeo.GetValue('XOS_SavedNation', $null) -or
                $null -ne $priorGeo.GetValue('XOS_SavedDeviceRegion', $null) -or
                $null -ne $priorGeo.GetValue('XOS_SavedGeoName', $null) -or
                $null -ne $priorGeo.GetValue('XOS_SavedNationExists', $null) -or
                $null -ne $priorGeo.GetValue('XOS_SavedDeviceRegionExists', $null) -or
                $null -ne $priorGeo.GetValue('XOS_SavedGeoNameExists', $null)
            if ($hasPendingSave) {
                $liveNation = [Microsoft.Win32.Registry]::GetValue($GeoKey, 'Nation', $null)
                $liveDeviceRegion = [Microsoft.Win32.Registry]::GetValue($DeviceRegionKey, 'DeviceRegion', $null)
                $liveName = [Microsoft.Win32.Registry]::GetValue($GeoKey, 'Name', $null)
                $savedNation = $priorGeo.GetValue('XOS_SavedNation', $null)
                $savedRegion = $priorGeo.GetValue('XOS_SavedDeviceRegion', $null)
                $savedName = $priorGeo.GetValue('XOS_SavedGeoName', $null)
                $liveMatchesSpoof = ("$liveNation" -eq "$TemporaryRegion" -and "$savedNation" -ne "$TemporaryRegion") -or
                    ("$liveDeviceRegion" -eq "$TemporaryRegion" -and "$savedRegion" -ne "$TemporaryRegion") -or
                    ("$liveName" -eq $TemporaryRegionName -and "$savedName" -ne $TemporaryRegionName)
                if ($liveMatchesSpoof) {
                    throw "A previous region spoof was never restored and the live values are still the temporary region. Refusing to overwrite the saved originals."
                }
                Write-Log 'A pending region save already exists and the live values look original, keeping it and skipping the save'
            } else {
                $nation = [Microsoft.Win32.Registry]::GetValue($GeoKey, 'Nation', $null)
                $geoName = [Microsoft.Win32.Registry]::GetValue($GeoKey, 'Name', $null)
                $deviceRegion = [Microsoft.Win32.Registry]::GetValue($DeviceRegionKey, 'DeviceRegion', $null)
                Write-Log "Saving region: Nation=$(if ($null -eq $nation) { 'not set' } else { $nation }); Name=$(if ($null -eq $geoName) { 'not set' } else { $geoName }); DeviceRegion=$(if ($null -eq $deviceRegion) { 'not set' } else { $deviceRegion })"
                $geo = [Microsoft.Win32.Registry]::Users.CreateSubKey('.DEFAULT\Control Panel\International\Geo')
                try {
                    $geo.SetValue('XOS_SavedNationExists', [int]($null -ne $nation), [Microsoft.Win32.RegistryValueKind]::DWord)
                    if ($null -ne $nation) { $geo.SetValue('XOS_SavedNation', [string]$nation, [Microsoft.Win32.RegistryValueKind]::String) }
                    else { $geo.DeleteValue('XOS_SavedNation', $false) }
                    $geo.SetValue('XOS_SavedGeoNameExists', [int]($null -ne $geoName), [Microsoft.Win32.RegistryValueKind]::DWord)
                    if ($null -ne $geoName) { $geo.SetValue('XOS_SavedGeoName', [string]$geoName, [Microsoft.Win32.RegistryValueKind]::String) }
                    else { $geo.DeleteValue('XOS_SavedGeoName', $false) }
                    $geo.SetValue('XOS_SavedDeviceRegionExists', [int]($null -ne $deviceRegion), [Microsoft.Win32.RegistryValueKind]::DWord)
                    if ($null -ne $deviceRegion) { $geo.SetValue('XOS_SavedDeviceRegion', [int]$deviceRegion, [Microsoft.Win32.RegistryValueKind]::DWord) }
                    else { $geo.DeleteValue('XOS_SavedDeviceRegion', $false) }
                } finally {
                    $geo.Close()
                }
            }
        } finally {
            $priorGeo.Close()
        }

        try {
            Invoke-DeviceRegionReg "add `"$RegionKey`" /v DeviceRegion /t REG_DWORD /d $TemporaryRegion /f"
            $appliedDeviceRegion = [Microsoft.Win32.Registry]::GetValue($DeviceRegionKey, 'DeviceRegion', $null)
            if ("$appliedDeviceRegion" -ne "$TemporaryRegion") {
                throw "Temporary DeviceRegion could not be verified: $appliedDeviceRegion"
            }
            [Microsoft.Win32.Registry]::SetValue($GeoKey, 'Nation', [string]$TemporaryRegion, [Microsoft.Win32.RegistryValueKind]::String)
            [Microsoft.Win32.Registry]::SetValue($GeoKey, 'Name', $TemporaryRegionName, [Microsoft.Win32.RegistryValueKind]::String)
            $appliedNation = [Microsoft.Win32.Registry]::GetValue($GeoKey, 'Nation', $null)
            $appliedGeoName = [Microsoft.Win32.Registry]::GetValue($GeoKey, 'Name', $null)
            if ([string]$appliedNation -ne [string]$TemporaryRegion -or [string]$appliedGeoName -ne $TemporaryRegionName) {
                throw "Temporary EEA region could not be verified: DeviceRegion=$appliedDeviceRegion; Nation=$appliedNation; Name=$appliedGeoName"
            }
            Write-Log "Temporary EEA region applied: DeviceRegion=$TemporaryRegion; Nation=$TemporaryRegion; Name=$TemporaryRegionName"
        } catch {
            $liveDeviceRegion = [Microsoft.Win32.Registry]::GetValue($DeviceRegionKey, 'DeviceRegion', $null)
            if ("$liveDeviceRegion" -ne "$TemporaryRegion") {
                $cleanupGeo = [Microsoft.Win32.Registry]::Users.OpenSubKey('.DEFAULT\Control Panel\International\Geo', $true)
                if ($cleanupGeo) {
                    try {
                        @('XOS_SavedNation', 'XOS_SavedNationExists', 'XOS_SavedGeoName', 'XOS_SavedGeoNameExists', 'XOS_SavedDeviceRegion', 'XOS_SavedDeviceRegionExists') |
                            ForEach-Object { $cleanupGeo.DeleteValue($_, $false) }
                    } finally {
                        $cleanupGeo.Close()
                    }
                }
                Write-Log 'Region spoof did not change DeviceRegion; cleared the pending region save'
            }
            throw
        }
    }

    "RestoreRegion" {
        $geo = [Microsoft.Win32.Registry]::Users.OpenSubKey('.DEFAULT\Control Panel\International\Geo', $true)
        if (-not $geo) { Write-Log 'Region key not found, nothing to restore'; return }
        $restored = $false
        try {
            $savedNation = $geo.GetValue('XOS_SavedNation', $null)
            $nationExists = $geo.GetValue('XOS_SavedNationExists', $null)
            if ($null -eq $nationExists -and $null -ne $savedNation) { $nationExists = 1 }
            if ($nationExists -eq 1) {
                if ($null -eq $savedNation) { throw 'Saved Nation value is missing' }
                $geo.SetValue('Nation', [string]$savedNation, [Microsoft.Win32.RegistryValueKind]::String)
            } elseif ($nationExists -eq 0) {
                $geo.DeleteValue('Nation', $false)
            }

            $savedGeoName = $geo.GetValue('XOS_SavedGeoName', $null)
            $geoNameExists = $geo.GetValue('XOS_SavedGeoNameExists', $null)
            if ($geoNameExists -eq 1) {
                if ($null -eq $savedGeoName) { throw 'Saved Geo Name value is missing' }
                $geo.SetValue('Name', [string]$savedGeoName, [Microsoft.Win32.RegistryValueKind]::String)
            } elseif ($geoNameExists -eq 0) {
                $geo.DeleteValue('Name', $false)
            }

            $savedDeviceRegion = $geo.GetValue('XOS_SavedDeviceRegion', $null)
            $deviceRegionExists = $geo.GetValue('XOS_SavedDeviceRegionExists', $null)
            $skipDeviceRegion = $false
            if ($null -eq $deviceRegionExists -and $null -ne $savedNation) {
                $legacyNation = 0
                $legacyRegion = [Microsoft.Win32.Registry]::GetValue($DeviceRegionKey, 'DeviceRegion', $null)
                if ([int]::TryParse([string]$savedNation, [ref]$legacyNation) -and $null -ne $legacyRegion -and @($TemporaryRegion, 244) -contains [int]$legacyRegion) {
                    $deviceRegionExists = 1
                    $savedDeviceRegion = $legacyNation
                    Write-Log 'Using legacy Nation marker to restore the spoofed DeviceRegion.'
                } else {
                    $skipDeviceRegion = $true
                    Write-Log 'Legacy region marker found without a spoofed DeviceRegion; leaving DeviceRegion unchanged.'
                }
            }
            if ($skipDeviceRegion) {
            } elseif ($deviceRegionExists -eq 1) {
                if ($null -eq $savedDeviceRegion) { throw 'Saved DeviceRegion value is missing' }
                Invoke-DeviceRegionReg "add `"$RegionKey`" /v DeviceRegion /t REG_DWORD /d $([int]$savedDeviceRegion) /f"
            } elseif ($deviceRegionExists -eq 0 -and $null -ne [Microsoft.Win32.Registry]::GetValue($DeviceRegionKey, 'DeviceRegion', $null)) {
                Invoke-DeviceRegionReg "delete `"$RegionKey`" /v DeviceRegion /f"
            }
            $restored = $true
            Write-Log 'Original region restored'
        } finally {
            if ($restored) {
                @('XOS_SavedNation', 'XOS_SavedNationExists', 'XOS_SavedGeoName', 'XOS_SavedGeoNameExists', 'XOS_SavedDeviceRegion', 'XOS_SavedDeviceRegionExists') |
                    ForEach-Object { $geo.DeleteValue($_, $false) }
            }
            $geo.Close()
        }
    }

    "BlockUpdater" {
        $policyKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\EdgeUpdate'
        [Microsoft.Win32.Registry]::SetValue($policyKey, 'Install{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        [Microsoft.Win32.Registry]::SetValue($policyKey, 'Update{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        Block-EdgeUpdater
    }

    { $_ -in "Browser", "Runtime" } {
        if ($Action -eq 'Runtime' -and [Microsoft.Win32.Registry]::GetValue($RuntimeStateKey, 'PreserveRuntime', 0) -eq 1) {
            $runtimePreserved = $true
            Write-Log 'Runtime removal skipped: WebView2 is preserved on this installation.'
            return
        }
        Stop-EdgeRemovalInfrastructure
        $comp = $Components[$Action]
        $clientState = Get-EdgeClientStatePath $comp.Guid

        if ($Action -eq 'Runtime') {
            Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name "Uninstall$($comp.Guid)" -ErrorAction SilentlyContinue
        }

        foreach ($uninstallKey in $comp.UninstallKeys) {
            Remove-ItemProperty -Path $uninstallKey -Name "NoRemove" -ErrorAction SilentlyContinue | Out-Null
        }

        if ($comp.EnableDevPolicy) {
            foreach ($devRoot in $EdgeUpdateDevRoots) {
                $dk = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey(
                    ($devRoot -replace '^HKLM:\\', ''))
                if ($dk) {
                    $dk.SetValue('AllowUninstall', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
                    $dk.Close()
                }
            }
        }

        if (-not (Test-Path $clientState)) {
            if ($Action -eq 'Runtime' -and -not (Invoke-WebView2Fallback)) {
                throw "WebView2 runtime files remain and no registered uninstaller is available."
            }
            Write-Log "Client state not found: $clientState"
            return
        }
        Remove-ItemProperty -Path $clientState -Name "experiment_control_labels" -ErrorAction SilentlyContinue | Out-Null

        $stubPath = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
        $stubFile = Join-Path $stubPath "MicrosoftEdge.exe"
        try {
            if (-not (Test-Path $stubFile)) {
                if (-not (Test-Path $stubPath)) { New-Item -ItemType Directory -Path $stubPath -Force | Out-Null }
                New-Item -ItemType File -Path $stubFile -Force | Out-Null
            }
        } catch { Write-Log "Could not create browser stub: $($_.Exception.Message)"; return }

        $info = Get-ItemProperty -Path $clientState
        $uninstallString = ([string]$info.UninstallString).Trim().Trim('"')
        if ([string]::IsNullOrEmpty($uninstallString)) {
            if ($Action -eq 'Runtime' -and -not (Invoke-WebView2Fallback)) {
                throw 'WebView2 runtime files remain and its registered uninstaller is missing.'
            }
            Write-Log 'Uninstall command is missing'
            return
        }
        if (-not (Test-Path $uninstallString)) {
            if ($Action -eq 'Runtime' -and -not (Invoke-WebView2Fallback)) {
                throw "WebView2 runtime files remain and its uninstaller was not found: $uninstallString"
            }
            Write-Log "Uninstaller not found: $uninstallString"
            return
        }

        $uninstallArguments = [string]$info.UninstallArguments
        $requiredSwitches = if ($Action -eq 'Runtime') {
            @('--uninstall', '--msedgewebview', '--system-level', '--verbose-logging', '--force-uninstall')
        } else {
            @('--uninstall', '--force-uninstall')
        }
        foreach ($switchName in $requiredSwitches) {
            $uninstallArguments = Add-UninstallSwitch $uninstallArguments $switchName
        }

        $origWinDir = $env:windir
        $process = $null
        try {
            if ([Environment]::OSVersion.Version.Build -lt 22000) { $env:windir = "" }
            Write-Log "Running uninstaller: $uninstallString $uninstallArguments"
            $process = Start-Process -FilePath $uninstallString -ArgumentList $uninstallArguments -WorkingDirectory (Split-Path -Path $uninstallString -Parent) -Wait -NoNewWindow -PassThru
            Write-Log "Uninstaller exit code: $($process.ExitCode)"
        } finally {
            $env:windir = $origWinDir
        }

        if ($Action -eq 'Runtime') {
            $remaining = @(Get-WebView2Executables)
            if ($remaining.Count -gt 0) {
                Write-Log 'Native WebView2 uninstaller did not fully remove the runtime; starting the protected cleanup fallback.'
            }
            if (-not (Invoke-WebView2Fallback)) {
                throw 'WebView2 runtime files remain after the native uninstaller and protected cleanup fallback.'
            }
        } else {
            $browserDirs = @(
                Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft\Edge\Application'
                Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Microsoft\Edge\Application'
            ) | Select-Object -Unique
            $browserState = Get-EdgeClientStatePath $comp.Guid
            $exeRemains = $false
            foreach ($browserDir in $browserDirs) {
                if (Test-Path (Join-Path $browserDir 'msedge.exe')) { $exeRemains = $true; break }
            }
            $keyRemains = Test-Path $browserState
            if ($exeRemains -or $keyRemains) {
                Write-Log "Browser uninstaller left Edge in place (exe remains=$exeRemains; registration remains=$keyRemains; exit code $($process.ExitCode)). The playbook's later cleanup removes the remaining files and keys."
            } else {
                Write-Log 'Edge removal verified: no browser executable and no Edge Update registration remain.'
            }
        }

        foreach ($lnk in $comp.Shortcuts) {
            if (Test-Path $lnk) { Remove-Item $lnk -Force }
        }
    }

}
} catch {
    Write-Log "Action failed: $($_.Exception.ToString())"
    throw
} finally {
    if ($Action -eq 'Runtime') {
        $present = Write-WebView2State
        if ($runtimePreserved) {
            Write-Log 'Runtime preservation complete. Installation state is logged above.'
        } elseif ($null -eq $present) {
            Write-Log 'WebView2 removal could not be verified. See the lines above.'
        } elseif ($present) {
            Write-Log 'WebView2 removal incomplete: runtime executable files remain. No permanent block was applied.'
        } else {
            [Microsoft.Win32.Registry]::SetValue($RuntimeStateKey, 'PreserveRuntime', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            Write-Log 'WebView2 removal verified: no shared runtime executable files remain. Empty folders are ignored.'
        }
    }
    Write-Log 'Action finished'
}
