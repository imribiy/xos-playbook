$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:ProgramData 'AME\Logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'EventChannelBackup.log'
function Write-Log { param([string]$m) "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Out-File $logFile -Append -Encoding utf8 }

$rootPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels'
$backupKey = 'HKLM:\SOFTWARE\XOSToolkit\EventChannelState'
$backupReg = Join-Path $env:SystemRoot 'service-backups\xos-event-channel-state.reg'

function Get-PropertyValue {
    param([object]$Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-CaptureComplete {
    try {
        $item = Get-ItemProperty -Path $backupKey -ErrorAction Stop
        if ([string]$item.CaptureStatus -ne 'Complete') { return $false }
        $total = Get-PropertyValue $item 'EnabledTotal'
        $chunks = Get-PropertyValue $item 'EnabledChunks'
        if ($null -eq $total -or $null -eq $chunks) { return $false }
        $count = 0
        for ($i = 0; $i -lt [int]$chunks; $i++) {
            $value = Get-PropertyValue $item ('Enabled' + $i)
            $chunkCount = Get-PropertyValue $item ('Enabled' + $i + 'Count')
            if ([string]::IsNullOrWhiteSpace([string]$value) -or $null -eq $chunkCount) { return $false }
            $items = @($value -split '\|')
            if ($items.Count -ne [int]$chunkCount) { return $false }
            $count += $items.Count
        }
        return $count -eq [int]$total
    } catch { return $false }
}

if (Test-CaptureComplete) {
    $capturedAt = (Get-ItemProperty -Path $backupKey -Name CapturedAt -ErrorAction SilentlyContinue).CapturedAt
    Write-Log "event channels were already captured and verified ($capturedAt), leaving them alone"
    exit 0
}

if (Test-Path -LiteralPath $backupKey) {
    Write-Log 'an incomplete event-channel capture was found, replacing it'
    Remove-Item -LiteralPath $backupKey -Recurse -Force -ErrorAction Stop
}

$root = Get-Item -LiteralPath $rootPath -ErrorAction Stop
$enabled = New-Object System.Collections.ArrayList
foreach ($name in $root.GetSubKeyNames()) {
    $sub = $null
    try {
        $sub = $root.OpenSubKey($name, $false)
        if ($sub -and $sub.GetValue('Enabled') -eq 1) { [void]$enabled.Add($name) }
    } finally { if ($sub) { $sub.Close() } }
}
$root.Close()

if (-not (Test-Path -LiteralPath $backupKey)) {
    New-Item -Path $backupKey -Force -ErrorAction Stop | Out-Null
}
New-ItemProperty -Path $backupKey -Name 'CaptureStatus' -Value 'Writing' -PropertyType String -Force -ErrorAction Stop | Out-Null

$chunkSize = 100
if ($enabled.Count -eq 0) {
    New-ItemProperty -Path $backupKey -Name 'EnabledChunks' -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
} else {
    for ($i = 0; $i -lt $enabled.Count; $i += $chunkSize) {
        $end = [Math]::Min($i + $chunkSize - 1, $enabled.Count - 1)
        $slice = @($enabled[$i..$end])
        $index = [int]($i / $chunkSize)
        New-ItemProperty -Path $backupKey -Name ('Enabled' + $index) -Value ($slice -join '|') -PropertyType String -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $backupKey -Name ('Enabled' + $index + 'Count') -Value $slice.Count -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -Path $backupKey -Name 'EnabledChunks' -Value ([int][Math]::Ceiling($enabled.Count / $chunkSize)) -PropertyType DWord -Force -ErrorAction Stop | Out-Null
}
New-ItemProperty -Path $backupKey -Name 'EnabledTotal' -Value $enabled.Count -PropertyType DWord -Force -ErrorAction Stop | Out-Null
New-ItemProperty -Path $backupKey -Name 'CapturedAt' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -PropertyType String -Force -ErrorAction Stop | Out-Null
New-ItemProperty -Path $backupKey -Name 'CaptureStatus' -Value 'Complete' -PropertyType String -Force -ErrorAction Stop | Out-Null

if (-not (Test-CaptureComplete)) { throw 'The event-channel capture did not verify after writing.' }

$backupDirectory = Split-Path -Path $backupReg -Parent
if (-not (Test-Path -LiteralPath $backupDirectory)) {
    New-Item -Path $backupDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
& reg.exe export 'HKLM\SOFTWARE\XOSToolkit\EventChannelState' $backupReg /y *> $null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupReg)) {
    throw "The event-channel registry export failed with exit code $LASTEXITCODE."
}
Write-Log "captured and verified $($enabled.Count) enabled event channels"
Write-Log "registry backup exported to $backupReg"
