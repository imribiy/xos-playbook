param(
    [Parameter(Mandatory = $true)]
    [string[]]$Names
)

$ErrorActionPreference = 'Stop'
$logFile = Join-Path $env:ProgramData 'AME\Logs\RemoveAppx.log'
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null

function Write-Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch { }
}

function Test-Target([string]$Name) {
    foreach ($pattern in $Names) {
        if ($Name -like ('*' + $pattern + '*')) { return $true }
    }
    return $false
}

function Test-ProtectedSystemPackage($Package) {
    if ([bool]$Package.NonRemovable) { return $true }
    return [string]$Package.Name -in @(
        'Microsoft.Windows.ContentDeliveryManager',
        'Microsoft.Windows.ParentalControls',
        'Microsoft.MicrosoftEdgeDevToolsClient',
        'Microsoft.XboxGameCallableUI'
    )
}

function Write-RemovalFailure($Package, [string]$Action, $ErrorRecord) {
    $fullName = [string]$Package.PackageFullName
    $message = if ($ErrorRecord -and $ErrorRecord.Exception) {
        [string]$ErrorRecord.Exception.Message
    } else {
        [string]$ErrorRecord
    }
    if (Test-ProtectedSystemPackage $Package) {
        Write-Log "Protected package removal refused: $fullName; Action=$Action; $message"
    } else {
        Write-Log "$Action failed: $fullName; $message"
    }
}

function Get-Targets {
    Get-AppxPackage -AllUsers -PackageTypeFilter Main,Bundle -ErrorAction Stop |
        Where-Object { Test-Target $_.Name }
}

function Get-RemovalParents($Packages) {
    $bundles = @($Packages | Where-Object { $_.IsBundle })
    $Packages | Where-Object {
        $pkg = $_
        $pkg.IsBundle -or -not @($bundles | Where-Object {
            $_.PackageFamilyName -eq $pkg.PackageFamilyName -and $_.Version -eq $pkg.Version
        }).Count
    } | Sort-Object PackageFullName -Unique
}

function Get-InstalledUsers($Package) {
    foreach ($user in @($Package.PackageUserInformation)) {
        $sid = [string]$user.UserSecurityId.Sid
        $state = [string]$user.InstallState
        if ($state -match '^(Installed|Staged)' -and $sid -match '^S-1-\d+(-\d+)+$') {
            $user
        }
    }
}

function Invoke-UserRemoval($Package) {
    $fullName = [string]$Package.PackageFullName
    foreach ($user in @(Get-InstalledUsers $Package)) {
        $sid = [string]$user.UserSecurityId.Sid
        try {
            Remove-AppxPackage -Package $fullName -User $sid -ErrorAction Stop
            Write-Log "User removal requested: $fullName; User=$sid"
        } catch {
            Write-RemovalFailure $Package "User removal; User=$sid" $_
        }
    }
}

function Remove-RegisteredPackage($Package, [switch]$Retry) {
    $fullName = $Package.PackageFullName
    $createdMarkers = @()
    try {
        if ($Retry) {
            if ($Package.NonRemovable) {
                Set-NonRemovableAppsPolicy -Online -PackageFamilyName $Package.PackageFamilyName -NonRemovable 0 -ErrorAction Stop | Out-Null
            }
            foreach ($user in $Package.PackageUserInformation) {
                $sid = [string]$user.UserSecurityId.Sid
                if ($sid -notmatch '^S-1-\d+(-\d+)+$') { continue }
                $marker = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\' + $sid + '\' + $fullName
                if (-not (Test-Path -LiteralPath $marker)) {
                    New-Item -Path $marker -Force -ErrorAction Stop | Out-Null
                    $createdMarkers += $marker
                }
            }
            [void](Invoke-UserRemoval $Package)
        }
        $allUsersFailed = $false
        try {
            Remove-AppxPackage -Package $fullName -AllUsers -ErrorAction Stop
            Write-Log "Removal requested: $fullName; Retry=$Retry"
        } catch {
            Write-RemovalFailure $Package "All-users removal" $_
            $allUsersFailed = $true
        }
        if ($allUsersFailed -and -not $Retry) {
            foreach ($pkg in @(Get-Targets | Where-Object { $_.PackageFullName -eq $fullName })) {
                [void](Invoke-UserRemoval $pkg)
            }
        }
        if ($Retry) {
            foreach ($pkg in @(Get-Targets | Where-Object { $_.PackageFullName -eq $fullName })) {
                [void](Invoke-UserRemoval $pkg)
            }
            try {
                Remove-AppxPackage -Package $fullName -AllUsers -ErrorAction Stop
                Write-Log "Second all-users removal requested: $fullName"
            } catch {
                Write-RemovalFailure $Package "Second all-users removal" $_
            }
        }
    } catch {
        Write-RemovalFailure $Package "Removal; Retry=$Retry" $_
    } finally {
        $remainingAfter = @()
        $stateUnknown = $false
        try {
            $remainingAfter = @(Get-Targets | Where-Object { $_.PackageFullName -eq $fullName })
        } catch {
            $stateUnknown = $true
            Write-Log "Could not read the remaining state of ${fullName}: $($_.Exception.Message)"
        }
        foreach ($marker in $createdMarkers) {
            if (($Retry -and $remainingAfter.Count -gt 0) -or $stateUnknown) {
                Write-Log "EndOfLife marker retained for pending removal: $marker"
                continue
            }
            try { Remove-Item -LiteralPath $marker -Force -ErrorAction Stop }
            catch { Write-Log "Temporary marker cleanup failed: $marker; $($_.Exception.Message)" }
        }
    }
}

try {
    Write-Log "Starting removal: $($Names -join ', ')"
    $provisioned = @()
    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { Test-Target $_.DisplayName })
    } catch {
        Write-Log "Provisioned package query failed, continuing with registered packages: $($_.Exception.Message)"
    }
    foreach ($pkg in $provisioned) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
            Write-Log "Deprovisioned: $($pkg.PackageName)"
        } catch {
            Write-Log "Deprovisioning failed: $($pkg.PackageName); $($_.Exception.Message)"
        }
    }

    $packages = @(Get-Targets)
    foreach ($pkg in @(Get-RemovalParents $packages)) {
        Remove-RegisteredPackage $pkg
    }
    $remaining = @(Get-Targets)
    foreach ($pkg in @(Get-RemovalParents $remaining)) {
        Remove-RegisteredPackage $pkg -Retry
    }

    $remaining = @(Get-Targets)
    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { Test-Target $_.DisplayName })
    } catch {
        Write-Log "Final provisioned package query failed: $($_.Exception.Message)"
        $provisioned = @()
    }
    foreach ($pkg in $remaining) {
        $users = @($pkg.PackageUserInformation | ForEach-Object { '{0}:{1}' -f $_.UserSecurityId.Sid, $_.InstallState })
        if (Test-ProtectedSystemPackage $pkg) {
            Write-Log "PROTECTED REMAINS: $($pkg.PackageFullName); Users=$($users -join ', ')"
        } else {
            Write-Log "REMAINS: $($pkg.PackageFullName); Users=$($users -join ', ')"
        }
    }
    foreach ($pkg in $provisioned) { Write-Log "STILL PROVISIONED: $($pkg.PackageName)" }
    Write-Log "Verified remaining: $($remaining.Count) registered/staged package(s), $($provisioned.Count) provisioned package(s)."
    $unexpectedRemaining = @($remaining | Where-Object { -not (Test-ProtectedSystemPackage $_) })
    $protectedCount = $remaining.Count - $unexpectedRemaining.Count
    if ($protectedCount -gt 0) {
        Write-Log "Protected system packages retained by Windows: $protectedCount"
    }
    if ($unexpectedRemaining.Count -or $provisioned.Count) { exit 1 }
    exit 0
} catch {
    Write-Log "AppX removal or verification failed: $($_.Exception.Message)"
    exit 1
}
