@echo off
rem Builds the Go core (from core\) into desktop\src-tauri\resources and then the Tauri installer.
rem Output: desktop\src-tauri\target\release\bundle\nsis\
setlocal EnableExtensions
cd /d "%~dp0.."
set "RES=desktop\src-tauri\resources"

echo ===================================
echo  Obsidian VPN desktop build
echo ===================================
echo.

if not exist "core\go.mod" (
    echo [error] core\ is empty. Run: git submodule update --init --recursive
    exit /b 1
)
if not exist "%RES%" mkdir "%RES%"

echo [1/5] obsidian-client.exe (windows/amd64)
pushd core
set "GOOS=windows"
set "GOARCH=amd64"
set "CGO_ENABLED=0"
go build -o "..\%RES%\obsidian-client.exe" ./cmd/client
set "RC=%errorlevel%"
set "GOOS="
set "GOARCH="
popd
if not "%RC%"=="0" goto :fail

echo [2/5] obsidian-server-linux (linux/amd64)
pushd core
set "GOOS=linux"
set "GOARCH=amd64"
set "CGO_ENABLED=0"
go build -o "..\%RES%\obsidian-server-linux" ./cmd/server
set "RC=%errorlevel%"
set "GOOS="
set "GOARCH="
set "CGO_ENABLED="
popd
if not "%RC%"=="0" goto :fail

echo [3/5] wintun.dll (pinned release, SHA256 verified)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fetch-wintun.ps1" -Destination "%RES%\wintun.dll"
if errorlevel 1 goto :fail

if not exist "%RES%\keyserver.py" (
    echo [error] %RES%\keyserver.py is missing
    exit /b 1
)

echo [4/5] npm dependencies
cd desktop
if not exist node_modules call npm ci
if errorlevel 1 goto :fail

echo [5/5] Tauri build
call npx tauri build
if errorlevel 1 goto :fail
cd ..

echo.
echo Done. Installer: desktop\src-tauri\target\release\bundle\nsis\
exit /b 0

:fail
echo.
echo Build failed.
exit /b 1
