# Downloads the pinned wintun 0.14.1 release and extracts bin/amd64/wintun.dll.
# Used by scripts/build-desktop.bat and .github/workflows/desktop.yml.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fetch-wintun.ps1 -Destination <path>

param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Url = 'https://www.wintun.net/builds/wintun-0.14.1.zip'
# SHA256 of the release zip, computed locally from the download above on 2026-10-08.
# No independent published checksum was available to cross-check against.
$ZipSha256 = '07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51'
# SHA256 of bin/amd64/wintun.dll inside that zip (matches the DLL previously committed to the repo).
$DllSha256 = 'e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce'

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$dest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
if ((Test-Path -LiteralPath $dest) -and ((Get-Sha256 $dest) -eq $DllSha256)) {
    Write-Host "wintun.dll already present and verified: $dest"
    exit 0
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("wintun-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $zip = Join-Path $work 'wintun.zip'
    Write-Host "Downloading $Url"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $zip

    $zipHash = Get-Sha256 $zip
    if ($zipHash -ne $ZipSha256) {
        throw "wintun.zip SHA256 mismatch: got $zipHash, expected $ZipSha256"
    }

    $extract = Join-Path $work 'extract'
    Expand-Archive -LiteralPath $zip -DestinationPath $extract
    $src = Get-ChildItem -LiteralPath $extract -Recurse -Filter 'wintun.dll' |
        Where-Object { $_.FullName -match '[\\/]bin[\\/]amd64[\\/]wintun\.dll$' } |
        Select-Object -First 1
    if (-not $src) {
        throw 'bin/amd64/wintun.dll not found in archive'
    }

    $dllHash = Get-Sha256 $src.FullName
    if ($dllHash -ne $DllSha256) {
        throw "wintun.dll SHA256 mismatch: got $dllHash, expected $DllSha256"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $src.FullName -Destination $dest -Force
    Write-Host "wintun.dll verified and written to $dest"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
