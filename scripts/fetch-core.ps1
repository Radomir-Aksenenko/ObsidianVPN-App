<#
.SYNOPSIS
Puts the ObsidianVPN core binaries into src-tauri\resources.

.DESCRIPTION
By default downloads obsidian-client.exe and obsidian-server-linux from the
GitHub release named in core-version.txt, checks them against sha256sums.txt
from the same release, and copies them into src-tauri\resources.

With -CoreSource, builds the same two binaries from a local checkout of the
core repository instead (requires Go on PATH).

.PARAMETER Tag
Release tag to download. Defaults to the value in core-version.txt.

.PARAMETER Repo
GitHub repository that publishes the core release.

.PARAMETER CoreSource
Path to a local checkout of the core repository. Builds from source instead of
downloading.
#>
[CmdletBinding()]
param(
    [string]$Tag,
    [string]$Repo = 'Radomir-Aksenenko/ObsidianVPN',
    [string]$CoreSource
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root 'src-tauri\resources'
$assets = @('obsidian-client.exe', 'obsidian-server-linux')

if (-not (Test-Path $dest)) {
    throw "Resources folder not found: $dest"
}

if ($CoreSource) {
    $src = (Resolve-Path $CoreSource).Path
    Write-Host "Building core from $src"
    Push-Location $src
    try {
        $env:CGO_ENABLED = '0'

        $env:GOOS = 'windows'
        $env:GOARCH = 'amd64'
        go build -trimpath -ldflags='-s -w' -o (Join-Path $dest 'obsidian-client.exe') ./cmd/client
        if ($LASTEXITCODE -ne 0) { throw 'go build of obsidian-client.exe failed' }

        $env:GOOS = 'linux'
        go build -trimpath -ldflags='-s -w' -o (Join-Path $dest 'obsidian-server-linux') ./cmd/server
        if ($LASTEXITCODE -ne 0) { throw 'go build of obsidian-server-linux failed' }
    }
    finally {
        Remove-Item Env:CGO_ENABLED, Env:GOOS, Env:GOARCH -ErrorAction SilentlyContinue
        Pop-Location
    }
    Write-Host 'Core binaries built from source.'
    return
}

if (-not $Tag) {
    $Tag = (Get-Content (Join-Path $root 'core-version.txt') -Raw).Trim()
}
if (-not $Tag) {
    throw 'core-version.txt is empty and no -Tag was given.'
}

$base = "https://github.com/$Repo/releases/download/$Tag"
Write-Host "Fetching core $Tag from $Repo"

$tmp = Join-Path ([IO.Path]::GetTempPath()) "obsidian-core-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $sumFile = Join-Path $tmp 'sha256sums.txt'
    Invoke-WebRequest -Uri "$base/sha256sums.txt" -OutFile $sumFile -UseBasicParsing

    $expected = @{}
    foreach ($line in Get-Content $sumFile) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
            $expected[$Matches[2].Trim()] = $Matches[1].ToLower()
        }
    }

    foreach ($name in $assets) {
        if (-not $expected.ContainsKey($name)) {
            throw "$name is not listed in sha256sums.txt of $Tag"
        }

        $file = Join-Path $tmp $name
        Invoke-WebRequest -Uri "$base/$name" -OutFile $file -UseBasicParsing

        $actual = (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower()
        if ($actual -ne $expected[$name]) {
            throw "SHA-256 mismatch for $name (expected $($expected[$name]), got $actual)"
        }

        Copy-Item -Path $file -Destination (Join-Path $dest $name) -Force
        Write-Host "OK $name"
    }
}
finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Core $Tag is in src-tauri\resources."
