param([ValidateSet('Apply', 'Boot')][string]$Mode = 'Apply')

$script:ScriptLog = Join-Path $env:ProgramData 'AME\Logs\XOS-Scripts.log'
function Write-ScriptLog([string]$Message) {
    try {
        if (!(Test-Path (Split-Path $script:ScriptLog -Parent))) {
            New-Item -Path (Split-Path $script:ScriptLog -Parent) -ItemType Directory -Force | Out-Null
        }
        ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ReservedStorage ' + $Mode + ': ' + $Message) |
            Out-File -FilePath $script:ScriptLog -Append -Encoding utf8
    } catch { }
}

function Get-ReservedStorageState {
    try { [string](Get-WindowsReservedStorageState -ErrorAction Stop).ReservedStorageState } catch { 'unknown' }
}

function Set-ReservedStorageDisabled {
    $out = & dism.exe /Online /Set-ReservedStorageState /State:Disabled /NoRestart 2>&1
    $code = $LASTEXITCODE
    $state = Get-ReservedStorageState
    Write-ScriptLog ('DISM exit ' + $code + ', state ' + $state)
    return ($state -eq 'Disabled' -or ($state -eq 'unknown' -and $code -eq 0))
}

$taskName = 'XOS-ReservedStorage'
$bootScript = Join-Path $env:SystemRoot 'XOS-RS.ps1'
$stateKey = 'HKLM:\SOFTWARE\XOSToolkit'
$triesValue = 'ReservedStorageBootTries'

if ($Mode -eq 'Apply') {
    if ((Get-ReservedStorageState) -eq 'Disabled' -or (Set-ReservedStorageDisabled)) {
        Write-ScriptLog 'disabled'
        exit 0
    }
    try {
        Copy-Item -LiteralPath $PSCommandPath -Destination $bootScript -Force -ErrorAction Stop
        if (!(Test-Path -LiteralPath $stateKey)) { New-Item -Path $stateKey -ErrorAction Stop | Out-Null }
        Remove-ItemProperty -LiteralPath $stateKey -Name $triesValue -ErrorAction SilentlyContinue
        $tr = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + $bootScript + ' -Mode Boot'
        & schtasks.exe /create /ru SYSTEM /rl HIGHEST /sc ONSTART /tn $taskName /tr $tr /f 2>&1 | Out-Null
        Write-ScriptLog ('reserved storage busy; boot retry task created, schtasks exit ' + $LASTEXITCODE)
    } catch {
        Write-ScriptLog ('boot retry setup failed: ' + $_.Exception.Message)
    }
    exit 0
}

$tries = 1 + [int](Get-ItemProperty -LiteralPath $stateKey -Name $triesValue -ErrorAction SilentlyContinue).$triesValue
Set-ItemProperty -LiteralPath $stateKey -Name $triesValue -Value $tries -Type DWord -ErrorAction SilentlyContinue
$done = $false
for ($i = 0; $i -lt 10; $i++) {
    if (!(Test-Path -LiteralPath $PSCommandPath)) { exit 0 }
    if ((Get-ReservedStorageState) -eq 'Disabled' -or (Set-ReservedStorageDisabled)) { $done = $true; break }
    Start-Sleep -Seconds 60
}
if (!(Test-Path -LiteralPath $PSCommandPath)) { exit 0 }
if ($done -or $tries -ge 5) {
    Write-ScriptLog ('finished after ' + $tries + ' boot(s), disabled=' + $done)
    & schtasks.exe /delete /tn $taskName /f 2>&1 | Out-Null
    Remove-ItemProperty -LiteralPath $stateKey -Name $triesValue -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
} else {
    Set-ItemProperty -LiteralPath $stateKey -Name $triesValue -Value $tries -Type DWord -ErrorAction SilentlyContinue
}
exit 0
