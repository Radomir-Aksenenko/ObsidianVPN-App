# ObsidianVPN desktop

Tauri 2 client. Screens follow the mockups in `ObsidianVPN-макеты`.

```
cd desktop
npm install
npm run tauri dev
```

Release build from the repo root: `build-gui.bat`.

The Go VPN core stays in `cmd/` and `obsidian/`. This app starts `obsidian-client.exe`, deploys `obsidian-server-linux` over SSH, and ships `keyserver.py` with the server.
