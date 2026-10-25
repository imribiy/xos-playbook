@echo off
SETLOCAL EnableDelayedExpansion

set "XOSLOG=%ProgramData%\AME\Logs\XOS-Scripts.log"
if not exist "%ProgramData%\AME\Logs" mkdir "%ProgramData%\AME\Logs" >nul 2>&1
set "XOSDATE=0000-00-00"
for /F "tokens=*" %%d in ('powershell -WindowStyle Hidden -NoProfile -NonInteractive -Command "(Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)"') do set "XOSDATE=%%d"

Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan" /v "Icon" /t REG_SZ /d "powercpl.dll" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan" /v "MUIVerb" /t REG_SZ /d "Choose Power Plan" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan" /v "Position" /t REG_SZ /d "Middle" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan" /v "SubCommands" /t REG_SZ /d "" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\01menu" /v "MUIVerb" /t REG_SZ /d "Power Saver" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\01menu" /v "Icon" /t REG_SZ /d "powercpl.dll" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\01menu\command" /ve /t REG_SZ /d "powercfg.exe /setactive a1841308-3541-4fab-bc81-f71556f20b4a" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\02menu" /v "MUIVerb" /t REG_SZ /d "Balanced" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\02menu" /v "Icon" /t REG_SZ /d "powercpl.dll" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\02menu\command" /ve /t REG_SZ /d "powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\03menu" /v "MUIVerb" /t REG_SZ /d "High Performance" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\03menu" /v "Icon" /t REG_SZ /d "powercpl.dll" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\03menu\command" /ve /t REG_SZ /d "powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\04menu" /v "MUIVerb" /t REG_SZ /d "XOS Power Plan" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\04menu" /v "Icon" /t REG_SZ /d "powercpl.dll" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\04menu\command" /ve /t REG_SZ /d "powercfg.exe /setactive 31693169-3169-3169-3169-316931693169" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\07menu" /v "MUIVerb" /t REG_SZ /d "Power Options" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\07menu" /v "Icon" /t REG_SZ /d "powercpl.dll" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\07menu" /v "CommandFlags" /t REG_DWORD /d "32" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\07menu\command" /ve /t REG_SZ /d "control.exe powercfg.cpl" /f >nul 2>&1

set "HasBattery=unknown"
for /F "tokens=*" %%b in ('powershell -WindowStyle Hidden -NoProfile -NonInteractive -Command "if (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue) { 'yes' } else { 'no' }"') do set "HasBattery=%%b"
echo [%XOSDATE% %TIME%] laptop-desktop: battery present=[!HasBattery!] >> "%XOSLOG%"
if /I "!HasBattery!"=="yes" (
    echo [%XOSDATE% %TIME%] laptop-desktop: taking LAPTOP branch because a battery is present >> "%XOSLOG%"
    goto LAPTOP
)

for /F "tokens=*" %%c in ('powershell -WindowStyle Hidden -NoProfile -NonInteractive -Command " (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes -join ',' "') do set "ChassisTypeString=%%c"
for /F "tokens=1 delims=," %%t in ("%ChassisTypeString%") do set "PrimaryChassisType=%%t"
set /A ChassisType=%PrimaryChassisType% 2>NUL

echo [%XOSDATE% %TIME%] laptop-desktop: ChassisTypes=[!ChassisTypeString!] primary=[!PrimaryChassisType!] >> "%XOSLOG%"

if not defined ChassisType (
    echo [%XOSDATE% %TIME%] laptop-desktop: no battery and no chassis type, taking DESKTOP branch >> "%XOSLOG%"
    goto DESKTOP
)

if %ChassisType% LEQ 7 (
    echo [%XOSDATE% %TIME%] laptop-desktop: taking DESKTOP branch, chassis %ChassisType% ^<= 7 >> "%XOSLOG%"
    goto DESKTOP
) else (
    echo [%XOSDATE% %TIME%] laptop-desktop: taking LAPTOP branch, chassis %ChassisType% ^> 7 >> "%XOSLOG%"
    goto LAPTOP
)

:DESKTOP
set "XOSDEVRESTORE=%SystemRoot%\service-backups\xos-device-power-restore.bat"
if not exist "%SystemRoot%\service-backups" mkdir "%SystemRoot%\service-backups" >nul 2>&1
if not exist "%XOSDEVRESTORE%" echo rem Originals of the device power values the XOS desktop tweaks overwrote. Run this to restore them.>"%XOSDEVRESTORE%"

call "%~dp0ApplyPowerPlan.bat" PowerPlan
powercfg /setacvalueindex 31693169-3169-3169-3169-316931693169 SUB_VIDEO VIDEOIDLE 0 >nul 2>&1
powercfg /setdcvalueindex 31693169-3169-3169-3169-316931693169 SUB_VIDEO VIDEOIDLE 0 >nul 2>&1
powercfg /setacvalueindex 31693169-3169-3169-3169-316931693169 SUB_SLEEP STANDBYIDLE 0 >nul 2>&1
powercfg /setdcvalueindex 31693169-3169-3169-3169-316931693169 SUB_SLEEP STANDBYIDLE 0 >nul 2>&1
powercfg /setacvalueindex 31693169-3169-3169-3169-316931693169 SUB_SLEEP HIBERNATEIDLE 0 >nul 2>&1
powercfg /setdcvalueindex 31693169-3169-3169-3169-316931693169 SUB_SLEEP HIBERNATEIDLE 0 >nul 2>&1
for %%a in (
	EnhancedPowerManagementEnabled
	AllowIdleIrpInD3
	EnableSelectiveSuspend
	DeviceSelectiveSuspended
	SelectiveSuspendEnabled
	SelectiveSuspendOn
	WaitWakeEnabled
	D3ColdSupported
	WdfDirectedPowerTransitionEnable
	EnableIdlePowerManagement
	IdleInWorkingState
	WakeEnabled
) do for /f "delims=" %%b in ('reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum" /s /f "%%a" ^| findstr "HKEY"') do (
	for /f "tokens=1,3" %%x in ('reg query "%%b" /v "%%a" 2^>nul ^| findstr /i "REG_DWORD"') do echo reg.exe add "%%b" /v "%%x" /t REG_DWORD /d %%y /f>>"%XOSDEVRESTORE%"
	reg query "%%b" /v "%%a" >nul 2>&1 && Reg.exe add "%%b" /v "%%a" /t REG_DWORD /d "0" /f >nul 2>&1
)
bcdedit /set disabledynamictick yes >nul 2>&1
powercfg -h off
powercfg /x monitor-timeout-dc 0
powercfg /x disk-timeout-dc 0
powercfg /x standby-timeout-dc 0
powercfg /x hibernate-timeout-dc 0
powercfg -SETACTIVE "31693169-3169-3169-3169-316931693169" >nul 2>&1
powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>nul
powercfg /SETDCVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>nul
powercfg /SETACTIVE SCHEME_CURRENT
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" /v "Attributes" /t REG_DWORD /d 2 /f >nul 2>&1
powercfg -SETACVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100 2>nul
powercfg -SETDCVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583 100 2>nul
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\ea062031-0e34-4ff1-9b6d-eb1059334028" /v "Attributes" /t REG_DWORD /d 2 /f >nul 2>&1
powercfg -SETACVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 ea062031-0e34-4ff1-9b6d-eb1059334028 100 2>nul
powercfg -SETDCVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 ea062031-0e34-4ff1-9b6d-eb1059334028 100 2>nul
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\943c8cb6-6f93-4227-ad87-e9a3feec08d1" /v "Attributes" /t REG_DWORD /d 2 /f >nul 2>&1
powercfg -SETACVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 943c8cb6-6f93-4227-ad87-e9a3feec08d1 100 2>nul
powercfg -SETDCVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 943c8cb6-6f93-4227-ad87-e9a3feec08d1 100 2>nul
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\f7277c87-9043-4248-9e8d-db20e412c751" /v "Attributes" /t REG_DWORD /d 2 /f >nul 2>&1
powercfg -SETACVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 f7277c87-9043-4248-9e8d-db20e412c751 0 2>nul
powercfg -SETDCVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 f7277c87-9043-4248-9e8d-db20e412c751 0 2>nul
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\df142941-20f1-4cc0-928d-fde8c3378dce" /v "Attributes" /t REG_DWORD /d 2 /f >nul 2>&1
powercfg -SETACVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 df142941-20f1-4cc0-928d-fde8c3378dce 0 2>nul
powercfg -SETDCVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 df142941-20f1-4cc0-928d-fde8c3378dce 0 2>nul
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\a55612aa-f624-42c6-a443-7397d064c04f" /v "Attributes" /t REG_DWORD /d 2 /f >nul 2>&1
powercfg -SETACVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 a55612aa-f624-42c6-a443-7397d064c04f 0 2>nul
powercfg -SETDCVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 a55612aa-f624-42c6-a443-7397d064c04f 0 2>nul
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\2430ab6f-a520-44a2-9601-f7f23b5134b1" /v "Attributes" /t REG_DWORD /d 2 /f >nul 2>&1
powercfg -SETACVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 2430ab6f-a520-44a2-9601-f7f23b5134b1 0 2>nul
powercfg -SETDCVALUEINDEX SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 2430ab6f-a520-44a2-9601-f7f23b5134b1 0 2>nul
powercfg -setactive SCHEME_CURRENT
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Cmbatt" /v "Start" /t REG_DWORD /d "4" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\acpiex" /v "Start" /t REG_DWORD /d "4" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\acpipagr" /v "Start" /t REG_DWORD /d "4" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\acpipmi" /v "Start" /t REG_DWORD /d "4" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\acpitime" /v "Start" /t REG_DWORD /d "4" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\bam" /v "Start" /t REG_DWORD /d "4" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power" /v "EnergyEstimationEnabled" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v "PowerThrottlingOff" /t REG_DWORD /d "1" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\05menu" /v "MUIVerb" /t REG_SZ /d "Disable Idle" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\05menu" /v "Icon" /t REG_SZ /d "powercpl.dll" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\05menu" /v "CommandFlags" /t REG_DWORD /d "32" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\05menu\command" /ve /t REG_SZ /d "cmd.exe /c powercfg -setacvalueindex scheme_current sub_processor 5d76a2ca-e8c0-402f-a133-2158492d58ad 1 && powercfg -setactive scheme_current" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\06menu" /v "MUIVerb" /t REG_SZ /d "Enable Idle" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\06menu" /v "Icon" /t REG_SZ /d "powercpl.dll" /f >nul 2>&1
Reg.exe add "HKCR\DesktopBackground\Shell\PowerPlan\shell\06menu\command" /ve /t REG_SZ /d "cmd.exe /c powercfg -setacvalueindex scheme_current sub_processor 5d76a2ca-e8c0-402f-a133-2158492d58ad 0 && powercfg -setactive scheme_current" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\USBHUB3\Parameters" /v "DisableLPM" /t REG_DWORD /d "1" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\USBHUB3\Parameters" /v "D3ColdSupported" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\USBHUB3\Parameters" /v "Ceip" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\USBHUB3\Parameters" /v "DisableSelectiveSuspendUI" /t REG_DWORD /d "1" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\usbccgp\Parameters" /v "D3ColdSupported" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\pci\Parameters" /v "D3ColdSupported" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\pci\Parameters" /v "D3ColdSupport" /t REG_DWORD /d "0" /f >nul 2>&1
Reg.exe add "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\MobilityCenter" /v "NoMobilityCenter" /t REG_DWORD /d "1" /f >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\iphlpsvc\Teredo" /v "AllowLowPowerMode" /t REG_DWORD /d "0" /f >nul 2>&1
wevtutil sl Microsoft-Windows-SleepStudy/Diagnostic /e:false >nul 2>&1
wevtutil sl Microsoft-Windows-Kernel-Processor-Power/Diagnostic /e:false >nul 2>&1
wevtutil sl Microsoft-Windows-UserModePowerService/Diagnostic /e:false >nul 2>&1
Reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\0012ee47-9041-4b5d-9b77-535fba8b1442\0b2d69d7-a2a1-449c-9680-f91c70521c60" /v "Attributes" /t REG_DWORD /d 2 /f >nul 2>&1
powercfg -SETACVALUEINDEX SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 0b2d69d7-a2a1-449c-9680-f91c70521c60 0 2>nul
powercfg -SETDCVALUEINDEX SCHEME_CURRENT 0012ee47-9041-4b5d-9b77-535fba8b1442 0b2d69d7-a2a1-449c-9680-f91c70521c60 0 2>nul
powercfg -setactive SCHEME_CURRENT
powershell -WindowStyle Hidden -NoProfile -NonInteractive -Command "Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue" >nul 2>&1
powershell -WindowStyle Hidden -NoProfile -NonInteractive -Command "Get-WmiObject MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Enable = $false; $_.psbase.Put() | Out-Null } catch {} }" >nul 2>&1
for /f "usebackq delims=" %%s in (`reg query HKU 2^>nul ^| findstr /r "S-1-5-21-[0-9]*-[0-9]*-[0-9]*-[0-9]*$"`) do reg.exe add "%%s\Software\Microsoft\input\Settings" /v "InsightsEnabled" /t REG_DWORD /d "0" /f >nul 2>&1
cls
goto :EOF

:LAPTOP
call "%~dp0ApplyPowerPlan.bat" PowerPlan
powercfg /setacvalueindex 31693169-3169-3169-3169-316931693169 SUB_VIDEO VIDEOIDLE 0 >nul 2>&1
powercfg /setdcvalueindex 31693169-3169-3169-3169-316931693169 SUB_VIDEO VIDEOIDLE 300 >nul 2>&1
powercfg /setacvalueindex 31693169-3169-3169-3169-316931693169 SUB_SLEEP STANDBYIDLE 0 >nul 2>&1
powercfg /setdcvalueindex 31693169-3169-3169-3169-316931693169 SUB_SLEEP STANDBYIDLE 900 >nul 2>&1
powercfg /setacvalueindex 31693169-3169-3169-3169-316931693169 SUB_SLEEP HIBERNATEIDLE 0 >nul 2>&1
powercfg /setdcvalueindex 31693169-3169-3169-3169-316931693169 SUB_SLEEP HIBERNATEIDLE 3600 >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\serenum" /v "Start" /t REG_DWORD /d "3" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\sermouse" /v "Start" /t REG_DWORD /d "3" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\serial" /v "Start" /t REG_DWORD /d "3" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\wlansvc" /v "Start" /t REG_DWORD /d "2" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\wmiacpi" /v "Start" /t REG_DWORD /d "2" /f >nul 2>&1
Reg.exe add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v "PowerThrottlingOff" /t REG_DWORD /d "0" /f >nul 2>&1
for %%v in (DisableLPM D3ColdSupported Ceip DisableSelectiveSuspendUI) do Reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Services\USBHUB3\Parameters" /v "%%v" /f >nul 2>&1
Reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Services\usbccgp\Parameters" /v "D3ColdSupported" /f >nul 2>&1
Reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Services\pci\Parameters" /v "D3ColdSupported" /f >nul 2>&1
powercfg -SETACVALUEINDEX 31693169-3169-3169-3169-316931693169 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>nul
powercfg -SETDCVALUEINDEX 31693169-3169-3169-3169-316931693169 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>nul
powercfg -SETACVALUEINDEX 31693169-3169-3169-3169-316931693169 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 1 2>nul
powercfg -SETDCVALUEINDEX 31693169-3169-3169-3169-316931693169 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 2 2>nul
powercfg -SETACVALUEINDEX 31693169-3169-3169-3169-316931693169 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 1200 2>nul
powercfg -SETDCVALUEINDEX 31693169-3169-3169-3169-316931693169 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 600 2>nul
powercfg -SETACVALUEINDEX 31693169-3169-3169-3169-316931693169 0012ee47-9041-4b5d-9b77-535fba8b1442 0b2d69d7-a2a1-449c-9680-f91c70521c60 2 2>nul
powercfg -SETDCVALUEINDEX 31693169-3169-3169-3169-316931693169 0012ee47-9041-4b5d-9b77-535fba8b1442 0b2d69d7-a2a1-449c-9680-f91c70521c60 3 2>nul
powercfg -setactive 31693169-3169-3169-3169-316931693169 >nul 2>&1
cls
