@echo off
setlocal
cd /d "%~dp0"

echo ===================================
echo  ObsidianVPN  (Tauri)
echo ===================================
echo.

echo [1/3] Core binaries
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fetch-core.ps1 %*
if errorlevel 1 exit /b 1

echo [2/3] Runtime payload
if exist wintun.dll copy /Y wintun.dll src-tauri\resources\wintun.dll >nul
if exist src-tauri\resources\keyserver.py goto payload_ok
echo Missing keyserver.py
exit /b 1
:payload_ok

echo [3/3] Tauri
if not exist node_modules call npm install
call npm run tauri build
if errorlevel 1 exit /b 1

echo.
echo Built under src-tauri\target\release\bundle
echo EXE: src-tauri\target\release\obsidian-vpn.exe
exit /b 0
