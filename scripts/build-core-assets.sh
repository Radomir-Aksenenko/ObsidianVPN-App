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

cp "$ROOT/wintun.dll" "$OUT/wintun.dll"
cp "$ROOT/desktop/src-tauri/resources/keyserver.py" "$OUT/keyserver.py"

echo "output: $(ls "$OUT" | wc -l) files in $OUT"
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "failed targets: ${FAILED[*]}" >&2
  exit 1
fi
echo "done"
