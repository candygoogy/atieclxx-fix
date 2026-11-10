@echo off
rem Double-click launcher: asks for admin, then opens the atieclxx-fix menu.
net session >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0atieclxx-fix.ps1"
echo.
pause
