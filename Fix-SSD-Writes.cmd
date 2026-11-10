@echo off
rem Double-click launcher: asks for admin once, then opens the atieclxx-fix menu.
rem fltmc only succeeds with admin rights and, unlike "net session", needs no service.
fltmc >nul 2>&1
if not errorlevel 1 goto run
if /i "%~1"=="--elevated" goto noadmin
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '--elevated' -Verb RunAs"
exit /b

:noadmin
echo Could not get administrator rights.
echo Right-click Fix-SSD-Writes.cmd and choose "Run as administrator".
pause
exit /b 1

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atieclxx-fix.ps1"
echo.
pause
