@echo off
REG QUERY "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode 2>nul | find /i "0x2" >nul
if not errorlevel 1 goto :done
REG ADD "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode /t REG_DWORD /d 2 /f >nul 2>&1
REG QUERY "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" /v ShellFeedsTaskbarViewMode 2>nul | find /i "0x2" >nul
if errorlevel 1 exit /b
tasklist /fi "imagename eq explorer.exe" 2>nul | find /i "explorer.exe" >nul
if not errorlevel 1 taskkill /f /im explorer.exe >nul 2>&1
start explorer.exe
:done
start /b "" cmd /c del "%~f0"&exit /b
