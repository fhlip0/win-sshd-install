@echo off
REM Run the PowerShell installer elevated (UAC prompt).
set "DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"%DIR%Install-OpenSSH-Server.ps1\"'"
