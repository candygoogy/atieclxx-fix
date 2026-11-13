@echo off
rem Double-click launcher: asks for admin once, then opens the atieclxx-fix menu.
rem Run from inside the zip, Windows unpacks only this file, so the script is missing.
if not exist "%~dp0atieclxx-fix.ps1" goto notextracted
rem fltmc only succeeds with admin rights and, unlike "net session", needs no service.
fltmc >nul 2>&1
if not errorlevel 1 goto run
if /i "%~1"=="--elevated" goto noadmin
rem The path goes through an environment variable, so a quote in it can't break the command.
set "ATIECLXX_FIX_SELF=%~f0"
powershell -NoProfile -Command "Start-Process -FilePath $env:ATIECLXX_FIX_SELF -ArgumentList '--elevated' -Verb RunAs"
exit /b

:notextracted
echo atieclxx-fix.ps1 is not next to this file.
echo.
echo Extract the whole zip first: right-click atieclxx-fix.zip and choose "Extract All",
echo then run Fix-SSD-Writes.cmd from the extracted folder.
echo.
pause
exit /b 1

:noadmin
echo Could not get administrator rights.
echo Right-click Fix-SSD-Writes.cmd and choose "Run as administrator".
pause
exit /b 1

:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atieclxx-fix.ps1"
echo.
pause
