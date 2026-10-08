#!/usr/bin/env bash
# Builds the bundled Go binaries into app/assets/bin/ (see app-docs/ARCHITECTURE.md,
# "Bundled binaries"). Sources come from core/ and the repo root.
# A failing target does not stop the others: failures are listed at the end and the
# script exits 1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/core"
OUT="$ROOT/app/assets/bin"
FAILED=()

# Pinned wintun release (same values as scripts/fetch-wintun.ps1).
WINTUN_URL='https://www.wintun.net/builds/wintun-0.14.1.zip'
WINTUN_ZIP_SHA256='07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51'
WINTUN_DLL_SHA256='e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce'

if ! command -v go >/dev/null 2>&1; then
  echo "error: go is required" >&2
  exit 1
fi

mkdir -p "$OUT"
export CGO_ENABLED=0

# build <goos> <goarch> <absolute output path> <package>
build() {
  echo "build $(basename "$3") ($1/$2)"
  (cd "$CORE" && GOOS="$1" GOARCH="$2" go build -trimpath -ldflags "-s -w" -o "$3" "$4")
}

# run <name> <build args...>: records the target as failed instead of aborting.
run() {
  local name="$1"
  shift
  build "$@" || FAILED+=("$name")
}

run obsidian-client-windows-amd64.exe windows amd64 "$OUT/obsidian-client-windows-amd64.exe" ./cmd/client
run obsidian-client-linux-amd64 linux amd64 "$OUT/obsidian-client-linux-amd64" ./cmd/client
run obsidian-server-linux-amd64 linux amd64 "$OUT/obsidian-server-linux-amd64" ./cmd/server
run obsidian-server-linux-arm64 linux arm64 "$OUT/obsidian-server-linux-arm64" ./cmd/server

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

DARWIN_AMD64="$TMP/client-darwin-amd64"
DARWIN_ARM64="$TMP/client-darwin-arm64"
if build darwin amd64 "$DARWIN_AMD64" ./cmd/client && build darwin arm64 "$DARWIN_ARM64" ./cmd/client; then
  if command -v lipo >/dev/null 2>&1; then
    lipo -create -output "$OUT/obsidian-client-darwin-universal" "$DARWIN_AMD64" "$DARWIN_ARM64"
  else
    echo "warning: lipo not found, obsidian-client-darwin-universal contains arm64 only" >&2
    cp "$DARWIN_ARM64" "$OUT/obsidian-client-darwin-universal"
  fi
else
  FAILED+=("obsidian-client-darwin-universal")
fi

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Puts a verified wintun.dll into $OUT. Uses the repo-root copy when its SHA256 matches,
# otherwise downloads the pinned release and extracts bin/amd64/wintun.dll. Any mismatch aborts.
stage_wintun() {
  local src="$ROOT/wintun.dll"
  local work="$TMP/wintun"
  local zip_hash dll_hash found

  if [ -f "$src" ] && [ "$(sha256_file "$src")" = "$WINTUN_DLL_SHA256" ]; then
    cp "$src" "$OUT/wintun.dll"
    echo "wintun.dll: repo copy verified"
    return 0
  fi

  echo "wintun.dll: repo copy missing or mismatched, downloading $WINTUN_URL"
  mkdir -p "$work/extract"
  curl -fsSL -o "$work/wintun.zip" "$WINTUN_URL"

  zip_hash="$(sha256_file "$work/wintun.zip")"
  if [ "$zip_hash" != "$WINTUN_ZIP_SHA256" ]; then
    echo "error: wintun.zip SHA256 mismatch: got $zip_hash, expected $WINTUN_ZIP_SHA256" >&2
    exit 1
  fi

  unzip -q "$work/wintun.zip" -d "$work/extract"
  found="$(find "$work/extract" -path '*/bin/amd64/wintun.dll' -type f | sed -n '1p')"
  if [ -z "$found" ]; then
    echo "error: bin/amd64/wintun.dll not found in archive" >&2
    exit 1
  fi

  dll_hash="$(sha256_file "$found")"
  if [ "$dll_hash" != "$WINTUN_DLL_SHA256" ]; then
    echo "error: wintun.dll SHA256 mismatch: got $dll_hash, expected $WINTUN_DLL_SHA256" >&2
    exit 1
  fi

  cp "$found" "$OUT/wintun.dll"
  echo "wintun.dll: downloaded and verified"
}

stage_wintun
cp "$ROOT/desktop/src-tauri/resources/keyserver.py" "$OUT/keyserver.py"

echo "output: $(ls "$OUT" | wc -l) files in $OUT"
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "failed targets: ${FAILED[*]}" >&2
  exit 1
fi
echo "done"
