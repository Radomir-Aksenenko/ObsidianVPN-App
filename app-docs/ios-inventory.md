# Old iOS client (SwiftUI + PacketTunnel): feature inventory

Sources: `ios/` (project.yml, Config/, ObsidianVPN/, PacketTunnel/, Shared/), Go API `core/pkg/mobile/mobile.go`.
Read the Swift sources for exact details of any item below.

## Screens
- Tabs: Главная, Серверы, Настройки.
- Home: connection orb (tap toggles; haptics), states ПОДКЛЮЧИТЬ / ОТМЕНА "Шифрование..." / ОТКЛЮЧИТЬ "Защищено" / ОСТАНОВКА. Ping chip. Tiles: speed down/up, ping (tap re-measures), session timer, split tile. Quick actions: ping, protocol info, log panel (copy all, clear).
- Servers: list, select, swipe favorite, swipe delete, "+" add. Empty state "Нет серверов".
- Add profile sheet: optional name, key field, QR scanner, paste, inline error.
- QR scanner: QR only, torch, camera permission states.
- Split tunnel: mode Выкл / Только список / Кроме списка; 4 presets; custom entries with multi paste and rejected-input reasons; warning when include list empty. Notes: domains re-resolved every 10 min, no wildcards, Cyrillic domains rejected (use xn--), iOS cannot split by app.
- Settings: auto-connect, kill switch (not wired), haptics.

## Data
- Profile: id UUID, name, city, countryCode, configURI (secret), isFavorite, splitTunnel (nil = off).
- Import prefixes obsidian://, vpn://, OBSDN-. Name: custom, then #fragment, then host:port, then "Obsidian Сервер". City/country from a keyword table (13 countries, English and Russian).
- Split fields in URI query: split_tunnel_mode, split_sites, legacy route_ips.
- App Group `group.com.obsidian.vpn`; keys vpn.profiles.v1, vpn.selected-profile.v1, vpn.active-config-uri.v1, vpn.runtime.logs.v1 (max 120), vpn.stats.rx/tx, lastTunnelError.

## PacketTunnelProvider
- Go: `MobileStartPacketTunnel(uri, 1280, nil, nil, nil)` -> session id; `MobileInjectPacket`; `MobileReceivePacket(sid, 100)` then drain with 0; `MobileStopTunnel`.
- Settings: tunnel remote = server IPv4 (resolved) or 10.8.0.1. IPv4 10.8.0.2/24, IPv6 fd00:8::2/64. DNS 1.1.1.1, 8.8.8.8, matchDomains [""]. MTU 1280 (Go caps BucketMTU to mtu-60).
- Loops: readPackets -> inject per packet in autoreleasepool; engine read on serial queue, 100 ms block then drain up to 64, write with protocol from IP version nibble.
- Memory: Go init sets SetMemoryLimit(8 MiB), GCPercent 40 (15 MB Jetsam limit). Route cap 2000 per list, 2 s DNS resolve budget.
- Split refresh timer 600 s, reapply only if route signature changed. Live split update via sendProviderMessage(JSON), extension replies "ok".
- Stats: app sends providerMessage "stats" every 1 s, reply `{tx, rx, running}`.
- Auto-connect via onDemandRules [NEOnDemandRuleConnect].

## Split tunnel
- Model: mode off/include/exclude, entries, presets {telegram, youtube, ru, local}. JSON keys split_tunnel_mode, split_sites, split_presets. Mode aliases: off/none; include/only/only_selected/vpn_only; exclude/except/all_except/bypass_selected.
- Rule grammar: `#` comments; IPv4/IPv6 host or CIDR; domains (ASCII, >= 2 labels, TLD not numeric, <= 253 chars); URLs reduced to host; wildcards and Cyrillic rejected; dedupe.
- Routes: off = default route, server excluded. exclude = default route minus server + IPs + resolved domains. include = only 1.1.1.1, 8.8.8.8 + IPs + resolved domains, matchDomains = domains.
- Presets: see `ios/Shared/SplitPresets.swift` (Telegram CIDRs + domains; YouTube/Google domains + Google ranges; 19 Russian service domains; local networks).

## IDs
App `com.obsidian.vpn`, extension `com.obsidian.vpn.PacketTunnel`, entitlements packet-tunnel-provider + app group `group.com.obsidian.vpn`. iOS 17.0+, Swift 5.10.

## Go mobile API (core/pkg/mobile/mobile.go)
- Interfaces: SocketProtector{Protect(fd int) bool}, StatusListener{OnStatusChange(status, detail string)}, StatsListener{OnStats(bytesSent, bytesRecv, txSpeed, rxSpeed int64)}.
- StartTunnelWithFd(uri, fd, mtu, p, s, st), StartTunnelWithConfig(json, fd, mtu, p, s, st), StartPacketTunnel(uri, mtu, p, s, st), StopTunnel, GetStats, InjectPacket, ReceivePacket(sid, timeoutMs), ParseConfigURI, StartLocalProxy, StopLocalProxy.

## Known gaps to fix
Kill switch not wired (use includeAllNetworks); secrets in UserDefaults; OBSDN profiles have no host (decode in Dart now); no ENOBUFS handling; hard-coded version.
