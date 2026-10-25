$runRoot = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$backupRoot = 'SOFTWARE\XOSToolkit\DefenderRunBackup'
$name = 'WindowsDefender'
$hklm = [Microsoft.Win32.Registry]::LocalMachine
try {
    $run = $hklm.OpenSubKey($runRoot, $false)
    if (-not $run) { exit 0 }
    try {
        if ($run.GetValueNames() -notcontains $name) { exit 0 }
        $kind = $run.GetValueKind($name)
        if (($kind -ne [Microsoft.Win32.RegistryValueKind]::String) -and ($kind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString)) { exit 0 }
        $data = [string]$run.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    } finally { $run.Close() }
    $existing = $hklm.OpenSubKey($backupRoot, $false)
    if ($existing) {
        try { if ($existing.GetValueNames() -contains $name) { exit 0 } } finally { $existing.Close() }
    }
    $backup = $hklm.CreateSubKey($backupRoot)
    try {
        $backup.SetValue($name, $data, $kind)
        $ok = ($backup.GetValueKind($name) -eq $kind) -and ([string]$backup.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -ceq $data)
        if (-not $ok) { $backup.DeleteValue($name, $false); Write-Output 'Run WindowsDefender backup did not verify' }
    } finally { $backup.Close() }
} catch {
    Write-Output ('Run WindowsDefender backup failed: ' + $_.Exception.Message)
}
