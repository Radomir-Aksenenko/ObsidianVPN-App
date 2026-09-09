@echo off
setlocal
cd /d "%~dp0"

echo ===================================
echo  ObsidianVPN  (Tauri)
echo ===================================
echo.

echo [1/4] Go client (Windows)
go build -o desktop\src-tauri\resources\obsidian-client.exe .\cmd\client
if errorlevel 1 exit /b 1

echo [2/4] Go server (Linux amd64)
set GOOS=linux
set GOARCH=amd64
go build -o desktop\src-tauri\resources\obsidian-server-linux .\cmd\server
set GOOS=
set GOARCH=
if errorlevel 1 exit /b 1

echo [3/4] Runtime payload
if exist wintun.dll copy /Y wintun.dll desktop\src-tauri\resources\wintun.dll >nul
if exist desktop\src-tauri\resources\keyserver.py goto payload_ok
echo Missing keyserver.py
exit /b 1
:payload_ok

echo [4/4] Tauri
cd desktop
if not exist node_modules call npm install
call npm run tauri build
if errorlevel 1 exit /b 1
cd ..

echo.
echo Built under desktop\src-tauri\target\release\bundle
echo EXE: desktop\src-tauri\target\release\obsidian-vpn.exe
exit /b 0
