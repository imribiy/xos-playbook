param(
    [ValidateSet('Core', 'AI', 'Printing', 'Defender')]
    [string]$Mode = 'Core'
)

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $env:ProgramData 'AME\Logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'ScheduledTaskDisable.log'
function Write-Log { param([string]$m) "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Out-File $logFile -Append -Encoding utf8 }

$coreTasks = @(
    '\Microsoft\Windows\UpdateOrchestrator\StartOobeAppsScan_LicenseAccepted',
    '\Microsoft\Windows\Application Experience\MareBackup',
    '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
    '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner',
    '\Microsoft\Windows\Diagnosis\Scheduled',
    '\Microsoft\Windows\FileHistory\File History (maintenance mode)',
    '\Microsoft\Windows\Registry\RegIdleBackup',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Data Integrity Scan\Data Integrity Check And Scan',
    '\Microsoft\Windows\Data Integrity Scan\Data Integrity Scan',
    '\Microsoft\Windows\Data Integrity Scan\Data Integrity Scan for Crash Recovery',
    '\Microsoft\Windows\DiskFootprint\Diagnostics',
    '\Microsoft\Windows\MemoryDiagnostic\ProcessMemoryDiagnosticEvents',
    '\Microsoft\Windows\MemoryDiagnostic\RunFullMemoryDiagnostic',
    '\Microsoft\Windows\WDI\ResolutionHost',
    '\Microsoft\Windows\RetailDemo\CleanupOfflineContent',
    '\Microsoft\Windows\RemoteAssistance\RemoteAssistanceTask',
    '\Microsoft\Windows\SettingSync\NetworkStateChangeTask',
    '\Microsoft\Windows\SettingSync\BackgroundUploadTask',
    '\Microsoft\Windows\Maps\MapsToastTask',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\AccountHealth\RecoverabilityToastTask',
    '\Microsoft\Windows\Diagnosis\UnexpectedCodepath',
    '\Microsoft\Windows\Hotpatch\Monitoring',
    '\Microsoft\Windows\Maintenance\WinSAT',
    '\Microsoft\Windows\MemoryDiagnostic\AutomaticOfflineMemoryDiagnostic',
    '\Microsoft\Windows\PerformanceTrace\RequestTrace',
    '\Microsoft\Windows\PerformanceTrace\WhesvcToast',
    '\Microsoft\Windows\Shell\FamilySafetyMonitor',
    '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
    '\Microsoft\Windows\UsageAndQualityInsights\UsageAndQualityInsights-MaintenanceTask',
    '\Microsoft\Windows\Sustainability\PowerGridForecastTask',
    '\Microsoft\Windows\Sustainability\SustainabilityTelemetry',
    '\Microsoft\Windows\CloudRestore\Backup',
    '\Microsoft\Windows\CloudRestore\Restore',
    '\Microsoft\Windows\InstallService\RestoreDevice',
    '\Microsoft\Windows\InstallService\ScanForUpdates',
    '\Microsoft\Windows\InstallService\ScanForUpdatesAsUser',
    '\Microsoft\Windows\InstallService\SmartRetry',
    '\Microsoft\Windows\InstallService\WakeUpAndContinueUpdates',
    '\Microsoft\Windows\InstallService\WakeUpAndScanForUpdates',
    '\Microsoft\Windows\WindowsUpdate\Scheduled Start',
    '\Microsoft\Windows\UpdateOrchestrator\Report policies',
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Maintenance Work',
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Scan',
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Scan Static Task',
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Wake To Work',
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Work',
    '\Microsoft\Windows\UpdateOrchestrator\UIEOrchestrator',
    '\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask',
    '\Microsoft\Windows\UpdateOrchestrator\Start Oobe Expedite Work',
    '\Microsoft\Windows\UpdateOrchestrator\StartOobeAppsScan_OobeAppReady',
    '\Microsoft\Windows\UpdateOrchestrator\StartOobeAppsScanAfterUpdate',
    '\Microsoft\Windows\UpdateOrchestrator\UUS Failover Task',
    '\Microsoft\Windows\WaaSMedic\PerformRemediation',
    '\Microsoft\Windows\UpdateOrchestrator\AC Power Download',
    '\Microsoft\Windows\UpdateOrchestrator\AC Power Install',
    '\Microsoft\Windows\UpdateOrchestrator\Backup Scan',
    '\Microsoft\Windows\UpdateOrchestrator\Battery Saver Deferred Install',
    '\Microsoft\Windows\UpdateOrchestrator\Driver Install',
    '\Microsoft\Windows\UpdateOrchestrator\Maintenance Install',
    '\Microsoft\Windows\UpdateOrchestrator\MusUx_LogonUpdateResults',
    '\Microsoft\Windows\UpdateOrchestrator\MusUx_UpdateInterval',
    '\Microsoft\Windows\UpdateOrchestrator\Policy Install',
    '\Microsoft\Windows\UpdateOrchestrator\Reboot',
    '\Microsoft\Windows\UpdateOrchestrator\Reboot_AC',
    '\Microsoft\Windows\UpdateOrchestrator\Reboot_Battery',
    '\Microsoft\Windows\UpdateOrchestrator\Refresh Settings',
    '\Microsoft\Windows\UpdateOrchestrator\Resume On Boot',
    '\Microsoft\Windows\UpdateOrchestrator\Schedule Retry Scan',
    '\Microsoft\Windows\UpdateOrchestrator\StartOobeAppsScan',
    '\Microsoft\Windows\UpdateOrchestrator\USO_Broker_Display',
    '\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker_Display',
    '\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker_ReadyToReboot',
    '\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Start',
    '\Microsoft\Windows\UpdateOrchestrator\Universal Orchestrator Idle Start',
    '\Microsoft\Windows\UpdateOrchestrator\UpdateAssistant',
    '\Microsoft\Windows\UpdateOrchestrator\UpdateAssistantAllUsersRun',
    '\Microsoft\Windows\UpdateOrchestrator\UpdateAssistantCalendarRun',
    '\Microsoft\Windows\UpdateOrchestrator\UpdateAssistantWakeupRun',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\WindowsUpdate\AUScheduledInstall',
    '\Microsoft\Windows\WindowsUpdate\AUSessionConnect',
    '\Microsoft\Windows\WindowsUpdate\Automatic App Update',
    '\Microsoft\Windows\WindowsUpdate\RUXIM\PLUGScheduler',
    '\Microsoft\Windows\WindowsUpdate\Scheduled Start With Network',
    '\Microsoft\Windows\WindowsUpdate\sih',
    '\Microsoft\Windows\WindowsUpdate\sihboot',
    '\Microsoft\Windows\WindowsUpdate\sihpostreboot',
    '\Microsoft\Windows\Customer Experience Improvement Program\Server\ServerCeipAssistant',
    '\Microsoft\Windows\Customer Experience Improvement Program\Server\ServerRoleCollector',
    '\Microsoft\Windows\Customer Experience Improvement Program\Server\ServerRoleUsageCollector',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\BthSQM',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\Uploader',
    '\Microsoft\Windows\AppxDeploymentClient\UCPD velocity'
)
$aiTasks = @(
    '\Microsoft\Windows\WindowsAI\Recall\PolicyConfiguration',
    '\Microsoft\Windows\WindowsAI\Settings\InitialConfiguration',
    '\Microsoft\Windows\WindowsAI\ClickToDo\ModelCachingIdle',
    '\Microsoft\Windows\WindowsAI\ClickToDo\ModelCachingLimit',
    '\Microsoft\Windows\WindowsAI\ClickToDo\ModelCachingUpdate'
)
$printingTasks = @(
    '\Microsoft\Windows\Printing\PrinterCleanupTask',
    '\Microsoft\Windows\Printing\PrintJobCleanupTask',
    '\Microsoft\Windows\Printing\EduPrintProv'
)
$defenderTasks = @(
    '\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance',
    '\Microsoft\Windows\Windows Defender\Windows Defender Cleanup',
    '\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan',
    '\Microsoft\Windows\Windows Defender\Windows Defender Verification',
    '\Microsoft\Windows\ExploitGuard\ExploitGuard MDM policy Refresh'
)

if ($Mode -eq 'Core') {
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($path in $coreTasks) { [void]$targets.Add($path) }
    Get-ScheduledTask -TaskPath '\Microsoft\Office\*' -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$targets.Add("$($_.TaskPath)$($_.TaskName)") }
} elseif ($Mode -eq 'AI') {
    $targets = $aiTasks
} elseif ($Mode -eq 'Printing') {
    $targets = $printingTasks
} else {
    $targets = $defenderTasks
}

function Get-TaskEnabledViaCom {
    param(
        [string]$TaskPath,
        [string]$TaskName
    )

    $service = $null
    $folder = $null
    $registeredTask = $null
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder($TaskPath.TrimEnd('\'))
        $registeredTask = $folder.GetTask($TaskName)
        return [bool]$registeredTask.Enabled
    } catch {
        return $null
    } finally {
        foreach ($comObject in @($registeredTask, $folder, $service)) {
            if ($null -ne $comObject) {
                try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($comObject) } catch { }
            }
        }
    }
}

function Test-TaskExists {
    param(
        [string]$TaskPath,
        [string]$TaskName
    )

    $service = $null
    $folder = $null
    $registeredTask = $null
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder($TaskPath.TrimEnd('\'))
        $registeredTask = $folder.GetTask($TaskName)
        return $true
    } catch {
        $codes = @($_.Exception, $_.Exception.InnerException) | Where-Object { $_ } | ForEach-Object { '{0:X8}' -f $_.HResult }
        if (@($codes | Where-Object { $_ -in @('80070002', '80070003') }).Count -gt 0) { return $false }
    } finally {
        foreach ($comObject in @($registeredTask, $folder, $service)) {
            if ($null -ne $comObject) {
                try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($comObject) } catch { }
            }
        }
    }
    return $null -ne (Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue)
}

function Test-TaskDisabled {
    param(
        [string]$TaskPath,
        [string]$TaskName
    )

    $enabled = Get-TaskEnabledViaCom -TaskPath $TaskPath -TaskName $TaskName
    if ($null -ne $enabled) { return -not [bool]$enabled }

    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    return $null -ne $task -and [string]$task.State -eq 'Disabled'
}

function Disable-TaskViaCom {
    param(
        [string]$TaskPath,
        [string]$TaskName
    )

    $service = $null
    $folder = $null
    $registeredTask = $null
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder($TaskPath.TrimEnd('\'))
        $registeredTask = $folder.GetTask($TaskName)
        if (-not [bool]$registeredTask.Enabled) { return $true }
        $registeredTask.Enabled = $false
        return -not [bool]$registeredTask.Enabled
    } catch {
        Write-Log ("COM task disable failed: $TaskPath$TaskName - " + $_.Exception.Message)
        return $false
    } finally {
        foreach ($comObject in @($registeredTask, $folder, $service)) {
            if ($null -ne $comObject) {
                try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($comObject) } catch { }
            }
        }
    }
}
$changed = 0
$already = 0
$missing = 0
$protectedSkipped = 0
$knownProtectedSkips = @(
    '\Microsoft\Windows\WDI\ResolutionHost'
)
$failed = New-Object System.Collections.Generic.List[string]
foreach ($path in $targets | Select-Object -Unique) {
    $idx = $path.LastIndexOf('\')
    if ($idx -lt 0) { [void]$failed.Add($path + ': invalid task path'); continue }
    $taskPath = $path.Substring(0, $idx + 1)
    $taskName = $path.Substring($idx + 1)
    if (-not (Test-TaskExists -TaskPath $taskPath -TaskName $taskName)) { $missing++; continue }
    if (Test-TaskDisabled -TaskPath $taskPath -TaskName $taskName) { $already++; continue }
    $done = $false
    for ($attempt = 1; $attempt -le 3 -and -not $done; $attempt++) {
        try {
            Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop | Out-Null
        } catch { }
        Start-Sleep -Milliseconds 300
        $done = Test-TaskDisabled -TaskPath $taskPath -TaskName $taskName
        if (-not $done) {
            & schtasks.exe /Change /TN $path /Disable *> $null
            $schTasksExit = $LASTEXITCODE
            Start-Sleep -Milliseconds 300
            $done = Test-TaskDisabled -TaskPath $taskPath -TaskName $taskName
            if (-not $done -and $attempt -eq 1 -and $schTasksExit -ne 0) {
                Write-Log "schtasks fallback returned exit=$schTasksExit for $path"
            }
        }
        if (-not $done) {
            $comDisabled = Disable-TaskViaCom -TaskPath $taskPath -TaskName $taskName
            Start-Sleep -Milliseconds 300
            $done = Test-TaskDisabled -TaskPath $taskPath -TaskName $taskName
            if (-not $done -and $comDisabled) {
                Write-Log "COM task disable reported success but verification remained enabled: $path"
            }
        }
    }    if ($done) {
        $changed++
    } elseif ($knownProtectedSkips -contains $path) {
        $protectedSkipped++
        Write-Log "PROTECTED SKIP: $path remained enabled after verified retries"
    } else {
        [void]$failed.Add($path)
    }
}

Write-Log "$Mode tasks: changed=$changed already=$already missing=$missing protectedSkipped=$protectedSkipped failed=$($failed.Count)"
foreach ($path in $failed) { Write-Log "FAILED: $path" }
if ($failed.Count -gt 0) { exit 1 }
exit 0
