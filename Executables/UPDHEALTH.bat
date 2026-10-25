@echo off
setlocal enabledelayedexpansion


set "code="
for /f "delims=" %%k in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "Update Health Tools" /d 2^>nul ^| findstr /i /c:"\Uninstall\{"') do (
    for %%g in (%%~nxk) do set "code=%%g"
)

if not defined code exit /b 0

msiexec /x !code! /qn /norestart >nul 2>nul
if errorlevel 1 exit /b 0

reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\UpdateHealthTools" /f >nul 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\rempl" /f >nul 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\CloudManagedUpdate" /f >nul 2>nul

rmdir /s /q "%ProgramW6432%\Microsoft Update Health Tools" >nul 2>nul

exit /b 0
