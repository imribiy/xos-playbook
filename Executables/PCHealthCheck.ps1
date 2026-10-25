$script:ScriptLog = Join-Path $env:ProgramData 'AME\Logs\XOS-Scripts.log'
function Write-ScriptLog([string]$Message) {
    try {
        if (!(Test-Path (Split-Path $script:ScriptLog -Parent))) {
            New-Item -Path (Split-Path $script:ScriptLog -Parent) -ItemType Directory -Force | Out-Null
        }
        ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] PCHealthCheck: ' + $Message) |
            Out-File -FilePath $script:ScriptLog -Append -Encoding utf8
    } catch { }
}

$upgradeCodes = @('{B66EAEDD-A542-4C86-8C4D-6135868CC47F}', '{B5D9E156-6D3D-4925-B789-6B7DD1C6B059}')
$installDirs = @(
    @{ Path = (Join-Path $env:ProgramFiles 'PCHealthCheck'); Label = 'Program Files'; Assignment = '1' },
    @{ Path = (Join-Path $env:LOCALAPPDATA 'PCHealthCheck'); Label = 'the user profile'; Assignment = '0' }
)

function Get-ComProperty($Object, [string]$Name, [object[]]$Arguments) {
    return $Object.GetType().InvokeMember($Name, [Reflection.BindingFlags]::GetProperty, $null, $Object, $Arguments)
}

function Get-ProductInfo($Installer, [string]$ProductCode, [string]$Property) {
    try { return [string](Get-ComProperty $Installer 'ProductInfo' @($ProductCode, $Property)) } catch { return '' }
}

$installer = $null
$lookupOk = $false
$products = New-Object System.Collections.Generic.List[string]
try {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    foreach ($upgradeCode in $upgradeCodes) {
        foreach ($code in @(Get-ComProperty $installer 'RelatedProducts' @([string]$upgradeCode))) {
            $code = [string]$code
            if ($code -and -not $products.Contains($code)) { $products.Add($code) }
        }
    }
    $lookupOk = $true
} catch {
    Write-ScriptLog ('FAILED: Windows Installer product lookup: ' + $_.Exception.Message)
}

$remaining = 0
$removedAssignments = @()
if ($lookupOk -and $products.Count -eq 0) {
    Write-ScriptLog 'SKIPPED: not installed, no Windows Installer product with a PC Health Check UpgradeCode'
}
foreach ($productCode in $products) {
    $label = ((Get-ProductInfo $installer $productCode 'ProductName') + ' ' + (Get-ProductInfo $installer $productCode 'VersionString')).Trim()
    $assignment = Get-ProductInfo $installer $productCode 'AssignmentType'
    $exitCode = $null
    try {
        $proc = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList @('/x', $productCode, '/qn', '/norestart') -Wait -PassThru -WindowStyle Hidden
        $exitCode = $proc.ExitCode
    } catch {
        $remaining++
        Write-ScriptLog ("FAILED: msiexec /x $productCode ($label) did not start: " + $_.Exception.Message)
        continue
    }
    $state = $null
    try { $state = [int](Get-ComProperty $installer 'ProductState' @([string]$productCode)) } catch { }
    if ($null -eq $state) {
        $remaining++
        Write-ScriptLog "FAILED: $productCode ($label) state could not be read after uninstall, msiexec exit $exitCode"
    } elseif ($state -eq -1) {
        $removedAssignments += $assignment
        Write-ScriptLog "OK: uninstalled $productCode ($label), msiexec exit $exitCode"
    } else {
        $remaining++
        Write-ScriptLog "FAILED: $productCode ($label) still registered, state $state, msiexec exit $exitCode"
    }
}

if (-not $lookupOk -or $remaining -gt 0) {
    Write-ScriptLog 'SKIPPED: folders and shortcuts kept because the product may still be registered'
    exit 0
}
if ($products.Count -eq 0) {
    foreach ($dir in $installDirs) {
        if (Test-Path -LiteralPath $dir.Path) {
            Write-ScriptLog ('SKIPPED: install folder in ' + $dir.Label + ' kept because no product with a known UpgradeCode owns it')
        }
    }
    exit 0
}

$removedDirs = @()
foreach ($dir in $installDirs) {
    if ($removedAssignments -notcontains $dir.Assignment) {
        if (Test-Path -LiteralPath $dir.Path) { Write-ScriptLog ('SKIPPED: install folder in ' + $dir.Label + ' kept because the removed product was not installed there') }
        continue
    }
    $removedDirs += $dir
    if (-not (Test-Path -LiteralPath $dir.Path)) { continue }
    Remove-Item -LiteralPath $dir.Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $dir.Path) {
        Write-ScriptLog ('FAILED: leftover install folder in ' + $dir.Label + ' could not be removed')
    } else {
        Write-ScriptLog ('OK: removed leftover install folder in ' + $dir.Label)
    }
}

$targets = @()
foreach ($dir in $removedDirs) { $targets += ($dir.Path.TrimEnd('\') + '\') }
foreach ($productCode in $products) { $targets += (Join-Path $env:SystemRoot ('Installer\' + $productCode + '\')) }

$lnkFiles = New-Object System.Collections.Generic.List[object]
$startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
Get-ChildItem -LiteralPath $startMenu -Filter '*.lnk' -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $lnkFiles.Add($_) }
$usersRoot = Split-Path $env:PUBLIC -Parent
Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    Get-ChildItem -LiteralPath (Join-Path $_.FullName 'Desktop') -Filter '*.lnk' -Force -ErrorAction SilentlyContinue | ForEach-Object { $lnkFiles.Add($_) }
    Get-ChildItem -LiteralPath (Join-Path $_.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs') -Filter '*.lnk' -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $lnkFiles.Add($_) }
}

$shell = $null
try { $shell = New-Object -ComObject WScript.Shell } catch { Write-ScriptLog ('FAILED: WScript.Shell not available, shortcuts not checked: ' + $_.Exception.Message) }
$removed = 0
if ($shell) {
    foreach ($lnk in $lnkFiles) {
        $target = ''
        try { $target = [string]$shell.CreateShortcut($lnk.FullName).TargetPath } catch { continue }
        if (-not $target) { continue }
        $match = $false
        foreach ($prefix in $targets) {
            if ($target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $match = $true; break }
        }
        if (-not $match) { continue }
        Remove-Item -LiteralPath $lnk.FullName -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $lnk.FullName) {
            Write-ScriptLog ('FAILED: shortcut ' + $lnk.Name + ' could not be removed')
        } else {
            $removed++
            Write-ScriptLog ('OK: removed shortcut ' + $lnk.Name)
        }
    }
    if ($removed -eq 0) { Write-ScriptLog 'SKIPPED: no shortcut points to PC Health Check' }
}
