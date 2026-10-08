# ObsidianVPN desktop

Tauri 2 client. Screens follow the mockups in `ObsidianVPN-макеты`.

The VPN core is not stored in this repository. The app bundles `obsidian-client.exe` and `obsidian-server-linux` from the [ObsidianVPN](https://github.com/Radomir-Aksenenko/ObsidianVPN) GitHub release named in `core-version.txt`. `scripts/fetch-core.ps1` downloads them, checks their SHA-256 against the release's `sha256sums.txt`, and copies them into `src-tauri/resources/`.

## Build

Release installer (Windows, from the repo root):

```
build-gui.bat
```

This fetches the core binaries, then runs `npm run tauri build`. The installer is written to `src-tauri\target\release\bundle\nsis\`.

To build the core from a local checkout of ObsidianVPN instead of the release (needs Go):

```
build-gui.bat -CoreSource ..\ObsidianVPN
```

Development:

```
powershell -ExecutionPolicy Bypass -File scripts\fetch-core.ps1
npm install
npm run tauri dev
```

## Updating the core

1. In ObsidianVPN, push a version tag, e.g. `git tag v0.2.0 && git push origin v0.2.0`. The `Release core binaries` workflow builds both binaries and attaches them to a release with that name.
2. Set `core-version.txt` to the new tag and open a PR here.

## CI

`.github/workflows/build-desktop.yml` runs on Windows: it fetches the core for the tag in `core-version.txt`, runs `npm ci` and `npm run tauri build`, and uploads the NSIS installer as the `obsidian-vpn-windows` artifact.
