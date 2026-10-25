param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Desktop", "LockScreen")]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$ImagePath
)

$logFile = Join-Path $env:ProgramData 'AME\Logs\XOS-Scripts.log'
function Write-Log {
    param([string]$m)
    try {
        $dir = Split-Path $logFile -Parent
        if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] SetWallpaper: ' + $m) | Out-File -FilePath $logFile -Append -Encoding utf8
    } catch { }
}

$resolvedPath = $null
try {
    $resolvedPath = (Resolve-Path $ImagePath -ErrorAction Stop).Path
} catch {
    Write-Log "image not found: $ImagePath"
    exit 1
}

if (-not $resolvedPath -or -not (Test-Path -LiteralPath $resolvedPath)) {
    Write-Log "image not found: $ImagePath"
    exit 1
}

$updated = 0
$skipped = 0
$cached = 0
$cacheSkipped = 0

switch ($Mode) {
    "Desktop" {
        Get-ChildItem -Path "Registry::HKU" -ErrorAction SilentlyContinue | ForEach-Object {
            $hive = $_

            try {
                [Microsoft.Win32.Registry]::SetValue("$($hive.Name)\Control Panel\Desktop", "WallPaper", $resolvedPath, [Microsoft.Win32.RegistryValueKind]::String)
                [Microsoft.Win32.Registry]::SetValue("$($hive.Name)\Control Panel\Desktop", "WallpaperStyle", "10", [Microsoft.Win32.RegistryValueKind]::String)
                [Microsoft.Win32.Registry]::SetValue("$($hive.Name)\Control Panel\Desktop", "TileWallpaper", "0", [Microsoft.Win32.RegistryValueKind]::String)
                $updated++
            } catch {
                $skipped++
            }

            try {
                [Microsoft.Win32.Registry]::SetValue(
                    "$($hive.Name)\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers",
                    "BackgroundHistoryPath0", $resolvedPath, [Microsoft.Win32.RegistryValueKind]::String)
            } catch { }

            try {
                $sid = Split-Path $hive.Name -Leaf
                $profile = $null
                $sidKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
                if (Test-Path -LiteralPath $sidKey) {
                    $profile = (Get-ItemProperty -LiteralPath $sidKey -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
                }
                if (-not $profile -and $sid -eq '.DEFAULT') {
                    $profile = Join-Path $env:SystemDrive 'Users\Default'
                }
                if ($profile -and (Test-Path -LiteralPath $profile)) {
                    $themes = Join-Path $profile 'AppData\Roaming\Microsoft\Windows\Themes'
                    if (-not (Test-Path -LiteralPath $themes)) { New-Item -ItemType Directory -Path $themes -Force | Out-Null }
                    Copy-Item -LiteralPath $resolvedPath -Destination (Join-Path $themes 'TranscodedWallpaper') -Force -ErrorAction Stop
                    $cached++
                } else {
                    $cacheSkipped++
                }
            } catch {
                $cacheSkipped++
            }
        }

        if (-not ([System.Management.Automation.PSTypeName]'XOS.WallpaperHelper').Type) {
            Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace XOS {
    public static class WallpaperHelper {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);

        public static int LastError { get; private set; }

        public static bool Apply(string path) {
            bool applied = SystemParametersInfo(0x0014, 0, path, 0x01 | 0x02);
            LastError = applied ? 0 : Marshal.GetLastWin32Error();
            return applied;
        }
    }
}
"@
        }
        $applied = $false
        $applyFailure = ''
        try {
            $applied = [XOS.WallpaperHelper]::Apply($resolvedPath)
            if (-not $applied) { $applyFailure = "Win32 error $([XOS.WallpaperHelper]::LastError)" }
        } catch { $applyFailure = $_.Exception.Message }
        Write-Log "desktop wallpaper requested=$resolvedPath; hives updated=$updated skipped=$skipped; theme cache written=$cached skipped=$cacheSkipped; applied live=$applied"
        if (-not $applied) {
            Write-Log "FAILED desktop wallpaper live application: $applyFailure"
            exit 1
        }
    }

    "LockScreen" {
        $lockDir = Join-Path $env:SystemRoot 'Web\Screen'
        if (-not (Test-Path $lockDir)) { New-Item -ItemType Directory -Path $lockDir -Force | Out-Null }
        $lockImg = Join-Path $lockDir 'lockscreen.jpg'
        Copy-Item -Path $resolvedPath -Destination $lockImg -Force

        $polPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
        try {
            if (-not (Test-Path $polPath)) { New-Item -Path $polPath -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $polPath -Name 'LockScreenImage' -Value $lockImg -Force -ErrorAction Stop
            Remove-ItemProperty -Path $polPath -Name 'NoChangingLockScreen' -Force -ErrorAction SilentlyContinue
            Write-Log "lock screen policy set to $lockImg"
        } catch {
            Write-Log "lock screen policy could not be written: $($_.Exception.Message)"
            exit 1
        }
    }
}
