# Builds the bundled Go binaries into app/assets/bin/ (see app-docs/ARCHITECTURE.md,
# "Bundled binaries"). Windows equivalent of build-core-assets.sh. A failing target
# does not stop the others: failures are listed at the end and the script exits 1.
$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot
$Core = Join-Path $Root 'core'
$Out = Join-Path $Root 'app\assets\bin'
$Failed = @()

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw 'go is required'
}
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$env:CGO_ENABLED = '0'

function Invoke-GoBuild([string]$GoOS, [string]$GoArch, [string]$Output, [string]$Package) {
    Write-Host "build $(Split-Path -Leaf $Output) ($GoOS/$GoArch)"
    $env:GOOS = $GoOS
    $env:GOARCH = $GoArch
    Push-Location $Core
    try {
        & go build -trimpath -ldflags '-s -w' -o $Output $Package | Out-Host
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        Pop-Location
        Remove-Item Env:GOOS, Env:GOARCH -ErrorAction SilentlyContinue
    }
}

function Add-Failure([bool]$Ok, [string]$Name) {
    if (-not $Ok) { $script:Failed += $Name }
}

Add-Failure (Invoke-GoBuild 'windows' 'amd64' (Join-Path $Out 'obsidian-client-windows-amd64.exe') './cmd/client') 'obsidian-client-windows-amd64.exe'
Add-Failure (Invoke-GoBuild 'linux' 'amd64' (Join-Path $Out 'obsidian-client-linux-amd64') './cmd/client') 'obsidian-client-linux-amd64'
Add-Failure (Invoke-GoBuild 'linux' 'amd64' (Join-Path $Out 'obsidian-server-linux-amd64') './cmd/server') 'obsidian-server-linux-amd64'
Add-Failure (Invoke-GoBuild 'linux' 'arm64' (Join-Path $Out 'obsidian-server-linux-arm64') './cmd/server') 'obsidian-server-linux-arm64'

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('obsidian-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
    $amd64 = Join-Path $Tmp 'client-darwin-amd64'
    $arm64 = Join-Path $Tmp 'client-darwin-arm64'
    $universal = Join-Path $Out 'obsidian-client-darwin-universal'
    $okAmd64 = Invoke-GoBuild 'darwin' 'amd64' $amd64 './cmd/client'
    $okArm64 = Invoke-GoBuild 'darwin' 'arm64' $arm64 './cmd/client'
    if ($okAmd64 -and $okArm64) {
        if (Get-Command lipo -ErrorAction SilentlyContinue) {
            & lipo -create -output $universal $amd64 $arm64
            if ($LASTEXITCODE -ne 0) { $script:Failed += 'obsidian-client-darwin-universal' }
        }
        else {
            Write-Warning 'lipo not found, obsidian-client-darwin-universal contains arm64 only'
            Copy-Item -Force $arm64 $universal
        }
    }
    else {
        $script:Failed += 'obsidian-client-darwin-universal'
    }
}
finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

# wintun.dll: use the repo-root copy when its SHA256 matches the pinned value, otherwise
# let fetch-wintun.ps1 download the pinned release, verify the zip and DLL hashes, and write it.
$WintunDll = Join-Path $Out 'wintun.dll'
$WintunRoot = Join-Path $Root 'wintun.dll'
$WintunDllSha256 = 'e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce'
$rootOk = (Test-Path -LiteralPath $WintunRoot) -and (((Get-FileHash -Algorithm SHA256 -LiteralPath $WintunRoot).Hash.ToLowerInvariant()) -eq $WintunDllSha256)
if ($rootOk) {
    Copy-Item -Force $WintunRoot $WintunDll
    Write-Host 'wintun.dll: repo copy verified'
}
else {
    Write-Host 'wintun.dll: repo copy missing or mismatched, fetching pinned release'
    try {
        & (Join-Path $PSScriptRoot 'fetch-wintun.ps1') -Destination $WintunDll
    }
    catch {
        Write-Error "wintun.dll fetch failed: $_"
        exit 1
    }
}
Copy-Item -Force (Join-Path $Root 'desktop\src-tauri\resources\keyserver.py') (Join-Path $Out 'keyserver.py')

Write-Host "output: $((Get-ChildItem $Out).Count) files in $Out"
if ($Failed.Count -gt 0) {
    Write-Error ('failed targets: ' + ($Failed -join ', '))
    exit 1
}
Write-Host 'done'
