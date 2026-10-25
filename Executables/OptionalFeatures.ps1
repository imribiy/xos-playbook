param(
    [string[]]$PrintingFeatures = @()
)

$PrintingFeatures = @($PrintingFeatures | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

$WarningPreference = 'SilentlyContinue'

$logDir = Join-Path $env:ProgramData 'AME\Logs'
$logFile = "$logDir\OptionalFeatures.log"
if (!(Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $logFile -Encoding utf8
}

Write-Log "--- OptionalFeatures script started ---"
$hadFailures = $false

$disable = @(
    "SMBDirect",
    "MSRDC-Infrastructure",
    "Workfolders-Client",
    "WCF-Services45",
    "WCF-TCP-PortSharing45",
    "Microsoft-Hyper-V-All",
    "Microsoft-Hyper-V",
    "Microsoft-Hyper-V-Tools-All",
    "Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Hypervisor",
    "Microsoft-Hyper-V-Services",
    "Microsoft-Hyper-V-Management-Clients"
) + $PrintingFeatures

$enable = @(
    "DirectPlay"
)

Write-Log "Querying all optional feature states..."
$allFeatures = @{}
try {
    Get-WindowsOptionalFeature -Online -ErrorAction Stop | ForEach-Object { $allFeatures[$_.FeatureName] = $_.State }
    Write-Log "Retrieved $($allFeatures.Count) features"
} catch {
    Write-Log "[FAILED] Could not enumerate optional features: $($_.Exception.Message)"
    exit 1
}

foreach ($f in $disable) {
    $state = $allFeatures[$f]
    if ($null -eq $state) {
        Write-Log "[SKIP] $f - not present on this system"
        continue
    }
    if ($state -eq "Disabled" -or $state -eq "DisabledWithPayloadRemoved") {
        Write-Log "[SKIP] $f - already disabled ($state)"
        continue
    }
    Write-Log "[DISABLE] $f - current state: $state"
    try {
        Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction Stop | Out-Null
    } catch {
        $hadFailures = $true
        Write-Log "[FAILED] $f - $($_.Exception.Message)"
        continue
    }
    $result = $null
    try { $result = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop).State } catch { }
    if ($null -eq $result) {
        Write-Log "[DONE] $f - state could not be read back after the disable; check DISM"
        continue
    }
    if ($result -notin @("Disabled", "DisabledWithPayloadRemoved", "DisablePending")) {
        $hadFailures = $true
        Write-Log "[FAILED] $f - unexpected resulting state: $result"
        continue
    }
    Write-Log "[DONE] $f - resulting state: $result"
}

foreach ($f in $enable) {
    $state = $allFeatures[$f]
    if ($null -eq $state) {
        Write-Log "[SKIP] $f - not present on this system"
        continue
    }
    if ($state -eq "Enabled") {
        Write-Log "[SKIP] $f - already enabled"
        continue
    }
    Write-Log "[ENABLE] $f - current state: $state"
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -All -ErrorAction Stop | Out-Null
    } catch {
        $hadFailures = $true
        Write-Log "[FAILED] $f - $($_.Exception.Message)"
        continue
    }
    $result = $null
    try { $result = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop).State } catch { }
    if ($null -eq $result) {
        Write-Log "[DONE] $f - state could not be read back after the enable; check DISM"
        continue
    }
    if ($result -notin @("Enabled", "EnablePending")) {
        $hadFailures = $true
        Write-Log "[FAILED] $f - unexpected resulting state: $result"
        continue
    }
    Write-Log "[DONE] $f - resulting state: $result"
}

$sr = Get-WindowsCapability -Online -Name "App.StepsRecorder~~~~0.0.1.0" -ErrorAction SilentlyContinue
if ($null -eq $sr -or [string]::IsNullOrEmpty($sr.Name)) {
    Write-Log "[SKIP] App.StepsRecorder - capability not present on this system"
} elseif ($sr.State -eq "Installed") {
    Write-Log "[REMOVE] App.StepsRecorder - current state: $($sr.State)"
    try {
        Remove-WindowsCapability -Online -Name "App.StepsRecorder~~~~0.0.1.0" -ErrorAction Stop | Out-Null
    } catch {
        $hadFailures = $true
        Write-Log "[FAILED] App.StepsRecorder - $($_.Exception.Message)"
        $sr = $null
    }
    if ($null -ne $sr) {
        $result = Get-WindowsCapability -Online -Name "App.StepsRecorder~~~~0.0.1.0" -ErrorAction SilentlyContinue
        $resultState = if ($null -eq $result) { "NotPresent" } else { $result.State }
        if ($resultState -notin @("NotPresent", "UninstallPending", "Removed")) {
            $hadFailures = $true
            Write-Log "[FAILED] App.StepsRecorder - unexpected resulting state: $resultState"
        } else {
            Write-Log "[DONE] App.StepsRecorder - resulting state: $resultState"
        }
    }
} else {
    Write-Log "[SKIP] App.StepsRecorder - not installed (state: $($sr.State))"
}

Write-Log "--- OptionalFeatures script finished ---"
if ($hadFailures) { exit 1 }
