$ErrorActionPreference = 'Stop'
$log = Join-Path $env:ProgramData 'AME\Logs\EdgeStartup.log'
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
function Write-StartupLog([string]$text) { Add-Content -LiteralPath $log -Encoding UTF8 -Value ('[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $text) }
$failed = 0
$removed = 0
foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryHive]::Users)) {
        $base = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
            $paths = if ($hive -eq [Microsoft.Win32.RegistryHive]::Users) {
                @($base.GetSubKeyNames() | Where-Object { $_ -match '^S-1-\d+(?:-\d+)+$' } | ForEach-Object { $_ + '\Software\Microsoft\Windows\CurrentVersion\Run' })
            } else { @('Software\Microsoft\Windows\CurrentVersion\Run') }
            foreach ($path in $paths) {
                $key = $null
                try {
                    $key = $base.OpenSubKey($path, $true)
                    if ($null -eq $key) { continue }
                    foreach ($name in @($key.GetValueNames() | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch*' })) {
                        $key.DeleteValue($name, $false)
                        if ($key.GetValueNames() -contains $name) { throw ('Readback still contains ' + $name) }
                        $removed++
                        Write-StartupLog ("REMOVED $hive $view $path $name")
                    }
                } catch {
                    $failed++
                    Write-StartupLog ("FAILED $hive $view $path : " + $_.Exception.Message)
                } finally { if ($null -ne $key) { $key.Dispose() } }
            }
        } catch {
            $failed++
            Write-StartupLog ("FAILED $hive $view : " + $_.Exception.Message)
        } finally { if ($null -ne $base) { $base.Dispose() } }
    }
}
Write-StartupLog ("RESULT removed=$removed failed=$failed")
if ($failed) { throw ("Edge startup cleanup failed on $failed registry locations; see $log") }
