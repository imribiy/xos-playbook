$currentBuild = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -EA SilentlyContinue).CurrentBuildNumber
$script:Log = Join-Path $env:ProgramData 'AME\Logs\XOS-Scripts.log'
function Write-SmLog([string]$Message) {
    try {
        $dir = Split-Path $script:Log -Parent
        if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] W11STARTMENU: ' + $Message) |
            Out-File -FilePath $script:Log -Append -Encoding utf8
    } catch { }
}

Write-SmLog "started on build $currentBuild"
if ($currentBuild -lt 22000) {
    Write-SmLog "build $currentBuild is below 22000, nothing to do"
    exit 0
}

Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue

Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount" -Recurse -Force -ErrorAction SilentlyContinue

$localState = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"
Remove-Item -Path "$localState\start.bin" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$localState\start2.bin" -Force -ErrorAction SilentlyContinue

Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process 'explorer.exe'
Write-SmLog "finished; Start Menu pins cleared and explorer restarted"
