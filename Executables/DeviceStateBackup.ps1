
$ErrorActionPreference = 'SilentlyContinue'

$backupDir = Join-Path $env:SystemRoot 'service-backups'
if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
$backupFile = Join-Path $backupDir 'disabled-devices.txt'
$logFile = Join-Path $env:ProgramData 'AME\Logs\DeviceStateBackup.log'
function Write-Log { param([string]$m) "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Out-File $logFile -Append -Encoding utf8 }

if (Test-Path $backupFile) {
    Write-Log "disabled device list already exists, leaving it alone"
    return
}

try {
    $devices = @(Get-PnpDevice -ErrorAction Stop)
} catch {
    Write-Log "the device list could not be read: $($_.Exception.Message)"
    return
}

$disabled = $devices | Where-Object { [string]$_.Status -eq 'Error' -and $_.InstanceId }
$recorded = New-Object System.Collections.ArrayList
foreach ($device in $disabled) {
    if ($device.Present -eq $false) { continue }
    if ($device.ConfigManagerErrorCode -eq 22) { [void]$recorded.Add($device.InstanceId) }
}

if ($recorded.Count -eq 0) {
    Set-Content -LiteralPath $backupFile -Value @('# No devices were disabled before the playbook ran.') -Encoding ASCII
    Write-Log "no disabled devices found; an empty list was recorded"
    return
}

Set-Content -LiteralPath $backupFile -Value ($recorded | Sort-Object) -Encoding ASCII
Write-Log "recorded $($recorded.Count) already-disabled device(s)"
