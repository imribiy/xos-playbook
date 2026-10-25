@echo off
SETLOCAL EnableDelayedExpansion

set "XOSLOG=%ProgramData%\AME\Logs\XOS-Scripts.log"
if not exist "%ProgramData%\AME\Logs" mkdir "%ProgramData%\AME\Logs" >nul 2>&1
set "XOSDATE=0000-00-00"
for /F "tokens=*" %%d in ('powershell -WindowStyle Hidden -NoProfile -NonInteractive -Command "(Get-Date).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)"') do set "XOSDATE=%%d"

set "HasBattery=unknown"
for /F "tokens=*" %%b in ('powershell -WindowStyle Hidden -NoProfile -NonInteractive -Command "if (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue) { 'yes' } else { 'no' }"') do set "HasBattery=%%b"
echo [%XOSDATE% %TIME%] network: battery present=[!HasBattery!] >> "%XOSLOG%"
if /I "!HasBattery!"=="yes" (
    echo [%XOSDATE% %TIME%] network: taking LAPTOP branch because a battery is present, NIC tweaks skipped >> "%XOSLOG%"
    goto LAPTOP
)

for /F "tokens=*" %%c in ('powershell -WindowStyle Hidden -NoProfile -NonInteractive -Command " (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes -join ',' "') do set "ChassisTypeString=%%c"
for /F "tokens=1 delims=," %%t in ("%ChassisTypeString%") do set "PrimaryChassisType=%%t"
set /A ChassisType=%PrimaryChassisType% 2>NUL

echo [%XOSDATE% %TIME%] network: ChassisTypes=[!ChassisTypeString!] primary=[!PrimaryChassisType!] >> "%XOSLOG%"

if not defined ChassisType (
    echo [%XOSDATE% %TIME%] network: no battery and no chassis type, taking DESKTOP branch >> "%XOSLOG%"
    goto DESKTOP
)

if %ChassisType% LEQ 7 (
    echo [%XOSDATE% %TIME%] network: taking DESKTOP branch, chassis %ChassisType% ^<= 7 >> "%XOSLOG%"
    goto DESKTOP
) else (
    echo [%XOSDATE% %TIME%] network: taking LAPTOP branch, chassis %ChassisType% ^> 7, NIC tweaks skipped >> "%XOSLOG%"
    goto LAPTOP
)

:DESKTOP

Reg.exe add "HKLM\System\CurrentControlSet\Services\Dnscache\Parameters" /v "DisableCoalescing" /t REG_DWORD /d "1" /f >nul 2>&1
Reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\Local" /v "fDisablePowerManagement" /t REG_DWORD /d "1" /f >nul 2>&1
Reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy" /v "fDisablePowerManagement" /t REG_DWORD /d "1" /f >nul 2>&1

set "WIFI_GUIDS= "
set "WIFI_KEYS= "
for /f "delims=" %%a in ('reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}" /s /f "*PhysicalMediaType" /d 2^>nul ^| findstr "HKEY"') do (
    for /f "tokens=3" %%t in ('reg query "%%a" /v "*PhysicalMediaType" 2^>nul ^| findstr /i "*PhysicalMediaType"') do (
        if "%%t"=="0x9" set "WIFI_KEYS=!WIFI_KEYS!%%~nxa "
        if "%%t"=="0x10" set "WIFI_KEYS=!WIFI_KEYS!%%~nxa "
    )
    for /f "tokens=3" %%g in ('reg query "%%a" /v "NetCfgInstanceId" 2^>nul ^| findstr /i "NetCfgInstanceId"') do set "IFGUIDS_%%~nxa=%%g"
)

for %%k in (!WIFI_KEYS!) do (
    for /f "tokens=2 delims==" %%v in ('set IFGUIDS_%%k 2^>nul') do set "WIFI_GUIDS=!WIFI_GUIDS!%%v "
)

echo [%XOSDATE% %TIME%] network: wireless adapters excluded from NIC tweaks: [!WIFI_GUIDS!] >> "%XOSLOG%"

for /f %%i in ('reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" 2^>nul ^| findstr "HKEY"') do (
    set "IFGUID=%%~ni"
    if "!WIFI_KEYS!"=="" (
        Reg.exe add "%%i" /v "TcpAckFrequency" /t REG_DWORD /d "1" /f >nul 2>&1
        Reg.exe add "%%i" /v "TCPNoDelay" /t REG_DWORD /d "1" /f >nul 2>&1
    ) else (
        echo !WIFI_GUIDS! | findstr /i /c:"!IFGUID! " >nul
        if errorlevel 1 (
            Reg.exe add "%%i" /v "TcpAckFrequency" /t REG_DWORD /d "1" /f >nul 2>&1
            Reg.exe add "%%i" /v "TCPNoDelay" /t REG_DWORD /d "1" /f >nul 2>&1
        )
    )
)

for /f %%a in ('reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}" /v "*SpeedDuplex" /s ^| findstr "HKEY"') do (

    set "THIS_KEY=%%~nxa "
    set "SKIP_KEY="
    if not "!WIFI_KEYS!"=="" echo !WIFI_KEYS! | findstr /i /c:"!THIS_KEY!" >nul && set "SKIP_KEY=1"
    if not defined SKIP_KEY (
        for %%v in (
            EnablePME
            #DeviceSleepOnDisconnect
            #EEE
            AdvancedEEE
            #SipsEnabled
            EnableAspm
            ASPM
            #ModernStandbyWoLMagicPacket
            #SelectiveSuspend
            EnableGigaLite
            GigaLite
            #WakeOnMagicPacket
            #WakeOnPattern
            AutoPowerSaveModeEnabled
            EEELinkAdvertisement
            EeePhyEnable
            EnableGreenEthernet
            EnableModernStandby
            PowerDownPll
            PowerSavingMode
            ReduceSpeedOnPowerDown
            S5WakeOnLan
            SavePowerNowEnabled
            ULPMode
            WakeOnLink
            WakeOnSlot
            WakeOnLinkChg
            WakeOnLinkUp
            WakeUpModeCap
            #NicAutoPowerSaver
            PowerSaveEnable
            EnablePowerManagement
            ForceWakeFromMagicPacketOnModernStandby
            WakeFromS5
            WakeOn
            EnableSavePowerNow
            #EnableDynamicPowerGating
            DynamicPowerGating
            EnableD3ColdInS0
            WakeFromPowerOff
            LogLinkStateEvent
        ) do (
            set "NICVAL=%%v"
            set "NICVAL=!NICVAL:#=*!"
            reg query "%%a" /v "!NICVAL!" >nul 2>&1 && Reg.exe add "%%a" /v "!NICVAL!" /t REG_SZ /d "0" /f >nul 2>&1
        )
        reg query "%%a" /v "PnPCapabilities" >nul 2>&1 && Reg.exe add "%%a" /v "PnPCapabilities" /t REG_DWORD /d "24" /f >nul 2>&1
        reg query "%%a" /v "WakeOnMagicPacketFromS5" >nul 2>&1 && Reg.exe add "%%a" /v "WakeOnMagicPacketFromS5" /t REG_SZ /d "2" /f >nul 2>&1
        reg query "%%a" /v "WolShutdownLinkSpeed" >nul 2>&1 && Reg.exe add "%%a" /v "WolShutdownLinkSpeed" /t REG_SZ /d "2" /f >nul 2>&1
    )
) >nul 2>&1

goto :END

:LAPTOP
goto :END

:END
exit /b 0
