import Foundation
import NetworkExtension
import Darwin
import Security

#if canImport(Obsidian)
import Obsidian
#endif

private let appGroupID = "group.com.obsidian.vpn"

/// Туннель Obsidian. Конфигурация приходит одним JSON (ClientConfig плюс split-поля):
/// Keychain по passwordReference, затем options["configJson"], затем providerConfiguration["configJson"] (старые профили).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let engine = ObsidianPacketEngine()
    private let receiveQueue = DispatchQueue(label: "com.obsidian.vpn.packet-receive", qos: .userInteractive)

    // Состояние, которое читают разные потоки. Все обращения через stateLock.
    private let stateLock = NSLock()
    private var running = false
    private var totalTxBytes: Int64 = 0
    private var totalRxBytes: Int64 = 0
    private var stage = 0
    private var engineStatus = ""

    // Раздельное туннелирование. Все изменения маршрутов идут через routeQueue.
    private let routeQueue = DispatchQueue(label: "com.obsidian.vpn.split-routes")
    private var activeSplit = SplitTunnelConfig()
    private var appliedSplitSignature: String?
    private var splitServerIP: String?
    private var splitServerIPv6: String?
    private var splitRefreshTimer: DispatchSourceTimer?
    // Только на routeQueue: применение маршрутов идёт по одному, остальные ждут в pendingReapplies.
    private var reapplyInFlight = false
    private var pendingReapplies: [() -> Void] = []
    private static let splitRefreshInterval: DispatchTimeInterval = .seconds(600)
    private static let splitResolveTimeout: TimeInterval = 2.0

    private var isRunning: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return running }
        set { stateLock.lock(); running = newValue; stateLock.unlock() }
    }

    /// Config for this start. The Keychain item is the normal source. options come from the app at start,
    /// and providerConfiguration only serves profiles saved by builds that stored the JSON in plain text.
    private func loadConfigJson(options: [String: NSObject]?) -> String? {
        if let json = configFromKeychain(), !json.isEmpty {
            return json
        }
        if let json = options?["configJson"] as? String, !json.isEmpty {
            return json
        }
        return (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["configJson"] as? String
    }

    /// Reads the Keychain item that passwordReference points to. The app writes it into the shared access group.
    private func configFromKeychain() -> String? {
        guard let reference = protocolConfiguration.passwordReference else { return nil }
        let query: [String: Any] = [
            kSecValuePersistentRef as String: reference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            tunnelLog("Не удалось прочитать конфигурацию из Keychain: статус \(status)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func setStage(_ value: Int) {
        stateLock.lock()
        stage = value
        stateLock.unlock()
    }

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        stateLock.lock()
        totalTxBytes = 0
        totalRxBytes = 0
        stage = 1
        engineStatus = "connecting"
        stateLock.unlock()

        let sharedDefaults = UserDefaults(suiteName: appGroupID) ?? .standard
        sharedDefaults.removeObject(forKey: "lastTunnelError")

        tunnelLog("Запрос на запуск туннеля")

        let configJson = loadConfigJson(options: options)

        guard let json = configJson, !json.isEmpty,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any] else {
            fail(TunnelProviderError.missingConfiguration, completionHandler)
            return
        }

        let rawHost = (fields["server_host"] as? String) ?? (protocolConfiguration.serverAddress ?? "")
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[] \n\t"))
        var serverIPv4: String?
        var serverIPv6: String?
        if IPv6Network.host(host) != nil {
            serverIPv6 = host
        } else {
            serverIPv4 = Self.resolveIPv4(host)
        }
        tunnelLog("Адрес сервера определен: \(serverIPv4 ?? serverIPv6 ?? "не найден")")

        let split = SplitTunnelConfig.decode(json: data) ?? SplitTunnelConfig()
        splitServerIP = serverIPv4
        splitServerIPv6 = serverIPv6
        let plan = makeSplitPlan(config: split, serverIP: serverIPv4, serverIPv6: serverIPv6)
        tunnelLog("Раздельное туннелирование: \(describeSplit(split, plan))")
        let settings = makeNetworkSettings(serverIP: serverIPv4, plan: plan)

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                // Провайдер уже освобождён: система всё равно ждёт ответа.
                completionHandler(TunnelProviderError.engine("Туннель остановлен до применения настроек."))
                return
            }
            if let error {
                self.fail(error, completionHandler, prefix: "Ошибка сетевых настроек: ")
                return
            }

            self.routeQueue.async {
                self.activeSplit = split
                self.appliedSplitSignature = plan.signature
            }
            self.setStage(2)

            tunnelLog("Сетевые настройки применены, запуск ядра Obsidian")
            do {
                try self.engine.start(configJson: json, mtu: 1280) { [weak self] status, detail in
                    self?.handleEngineStatus(status, detail)
                }
                self.isRunning = true
                self.setStage(3)
                self.readFromSystem()
                self.readFromEngine()
                self.routeQueue.async { self.scheduleSplitRefresh() }
                tunnelLog("Ядро Obsidian запущено")
                completionHandler(nil)
            } catch {
                self.fail(error, completionHandler, prefix: "Ошибка ядра: ")
            }
        }
    }

    private func fail(_ error: Error, _ completion: (Error?) -> Void, prefix: String = "") {
        let msg = prefix + error.localizedDescription
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        defaults.set(msg, forKey: "lastTunnelError")
        tunnelLog("ОШИБКА: \(msg)")
        completion(error)
    }

    /// Статусы из Go-ядра: connecting, connected, reconnecting, error, disconnected.
    private func handleEngineStatus(_ status: String, _ detail: String) {
        let value = status.lowercased()
        stateLock.lock()
        engineStatus = value
        if value == "connected" { stage = 4 }
        stateLock.unlock()
        tunnelLog("Ядро: \(value)")

        if value == "disconnected" && isRunning {
            // Сессия Go завершилась сама (без stopTunnel): туннель без ядра только глотает трафик.
            cancelTunnelWithError(nil)
        } else if value == "error" {
            let msg = detail.isEmpty ? "Ошибка соединения" : detail
            let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
            defaults.set(msg, forKey: "lastTunnelError")
            cancelTunnelWithError(TunnelProviderError.engine(msg))
        }
    }

    // MARK: - Split tunneling

    /// Резолвит домены (с таймаутом) и строит план маршрутов. Блокирует поток до 2 секунд при доменах.
    private func makeSplitPlan(config: SplitTunnelConfig, serverIP: String?, serverIPv6: String?) -> SplitRoutePlan {
        var resolved: [String] = []
        if config.mode != .off {
            let domains = config.rules.domains
            if !domains.isEmpty {
                resolved = DomainResolver.resolve(domains, timeout: Self.splitResolveTimeout)
            }
        }
        return SplitRouteBuilder.plan(
            config: config,
            serverIP: serverIP,
            serverIPv6: serverIPv6,
            resolvedIPs: resolved
        )
    }

    private func makeNetworkSettings(serverIP: String?, plan: SplitRoutePlan) -> NEPacketTunnelNetworkSettings {
        let remote = serverIP ?? splitServerIPv6 ?? "10.8.0.1"
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remote)
        let ipv4 = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])

        if plan.useDefaultRoute {
            ipv4.includedRoutes = [NEIPv4Route.default()]
            ipv4.excludedRoutes = plan.excludedRoutes.map {
                NEIPv4Route(destinationAddress: $0.addressString, subnetMask: $0.maskString)
            }
        } else {
            ipv4.includedRoutes = plan.includedRoutes.map {
                NEIPv4Route(destinationAddress: $0.addressString, subnetMask: $0.maskString)
            }
        }
        settings.ipv4Settings = ipv4

        // IPv6: в режимах с маршрутом по умолчанию весь v6 идет в туннель. Ядро отвечает на неподдерживаемые
        // v6-пакеты локально, поэтому приложения быстро переходят на IPv4.
        let ipv6 = NEIPv6Settings(addresses: ["fd00:8::2"], networkPrefixLengths: [NSNumber(value: 64)])
        if plan.useDefaultRoute {
            ipv6.includedRoutes = [NEIPv6Route.default()]
            ipv6.excludedRoutes = plan.excludedRoutes6.map {
                NEIPv6Route(destinationAddress: $0.addressString, networkPrefixLength: NSNumber(value: $0.prefix))
            }
        } else {
            ipv6.includedRoutes = plan.includedRoutes6.map {
                NEIPv6Route(destinationAddress: $0.addressString, networkPrefixLength: NSNumber(value: $0.prefix))
            }
        }
        settings.ipv6Settings = ipv6

        let dns = NEDNSSettings(servers: SplitRouteBuilder.tunnelDNSServers)
        dns.matchDomains = plan.matchDomains
        settings.dnsSettings = dns
        // MTU 1280: без фрагментации в любых мобильных сетях.
        settings.mtu = 1280
        return settings
    }

    /// Вызывается на routeQueue. Перечитывает домены и применяет маршруты.
    /// Без force настройки не переотправляются, если набор маршрутов не изменился.
    private func reapplySplit(_ config: SplitTunnelConfig, force: Bool, completion: @escaping (Bool) -> Void) {
        guard isRunning else {
            completion(false)
            return
        }

        // Одно применение за раз. Иначе таймер на 600 с, прочитавший старый activeSplit, мог бы закончиться
        // позже сообщения из приложения и вернуть старые правила. Запросы от пользователя ждут очереди,
        // запрос таймера просто пропускается: следующий тик повторит.
        if reapplyInFlight {
            if force {
                pendingReapplies.append { [weak self] in
                    guard let self else {
                        completion(false)
                        return
                    }
                    self.reapplySplit(config, force: true, completion: completion)
                }
            } else {
                completion(false)
            }
            return
        }

        let plan = makeSplitPlan(config: config, serverIP: splitServerIP, serverIPv6: splitServerIPv6)
        if !force && plan.signature == appliedSplitSignature {
            completion(true)
            return
        }

        let settings = makeNetworkSettings(serverIP: splitServerIP, plan: plan)
        reapplyInFlight = true
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completion(false)
                return
            }
            self.routeQueue.async {
                if let error {
                    tunnelLog("ОШИБКА: не удалось обновить раздельное туннелирование: \(error.localizedDescription)")
                    completion(false)
                } else {
                    self.activeSplit = config
                    self.appliedSplitSignature = plan.signature
                    tunnelLog("Раздельное туннелирование обновлено: \(self.describeSplit(config, plan))")
                    completion(true)
                }
                self.reapplyInFlight = false
                let queued = self.pendingReapplies
                self.pendingReapplies.removeAll()
                for next in queued { next() }
            }
        }
    }

    /// Раз в 10 минут перерезолвим домены: CDN меняет IP. Настройки переотправляются только при изменениях.
    private func scheduleSplitRefresh() {
        splitRefreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: routeQueue)
        timer.schedule(
            deadline: .now() + Self.splitRefreshInterval,
            repeating: Self.splitRefreshInterval,
            leeway: .seconds(30)
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            let config = self.activeSplit
            guard config.mode != .off, !config.rules.domains.isEmpty else { return }
            self.reapplySplit(config, force: false) { _ in }
        }
        timer.resume()
        splitRefreshTimer = timer
    }

    private func describeSplit(_ config: SplitTunnelConfig, _ plan: SplitRoutePlan) -> String {
        let modeName: String
        switch config.mode {
        case .off: modeName = "выкл"
        case .include: modeName = "только выбранное через VPN"
        case .exclude: modeName = "всё, кроме выбранного"
        }
        var text = "\(modeName), маршрутов v4: \(plan.routeCount), v6: \(plan.routeCount6), доменов: \(config.rules.domains.count)"
        if plan.truncated {
            text += ", список обрезан до \(SplitRouteBuilder.maxRoutes)"
        }
        return text
    }

    /// IPv4-литерал возвращается как есть, имя резолвится через getaddrinfo (AF_INET).
    private static func resolveIPv4(_ host: String) -> String? {
        guard !host.isEmpty else { return nil }
        var sin = sockaddr_in()
        if host.withCString({ inet_pton(AF_INET, $0, &sin.sin_addr) }) == 1 {
            return host
        }

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>? = nil
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(first) }
        guard let addrPtr = first.pointee.ai_addr else { return nil }
        let addr = addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var ipAddr = addr.sin_addr
        guard inet_ntop(AF_INET, &ipAddr, &ipBuf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: ipBuf)
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        isRunning = false
        routeQueue.async { [weak self] in
            guard let self else { return }
            self.splitRefreshTimer?.cancel()
            self.splitRefreshTimer = nil
            // Ждущие применения получат отказ (isRunning уже false), чтобы приложение не зависло на ответе.
            let queued = self.pendingReapplies
            self.pendingReapplies.removeAll()
            for next in queued { next() }
        }
        engine.stop()
        let reasonStr = stopReasonString(reason)
        tunnelLog("Туннель остановлен iOS. Причина: \(reasonStr)")
        if reason != .userInitiated && reason != .none {
            let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
            if defaults.string(forKey: "lastTunnelError") == nil {
                defaults.set("Остановлено системой (\(reasonStr))", forKey: "lastTunnelError")
            }
        }
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // JSON-сообщение: новые правила раздельного туннелирования (весь конфиг или только split-поля).
        if messageData.first == UInt8(ascii: "{") {
            guard let config = SplitTunnelConfig.decode(json: messageData) else {
                completionHandler?(nil)
                return
            }
            routeQueue.async { [weak self] in
                guard let self else {
                    completionHandler?(nil)
                    return
                }
                self.reapplySplit(config, force: true) { ok in
                    completionHandler?(ok ? Data("ok".utf8) : nil)
                }
            }
            return
        }

        stateLock.lock()
        let reply: [String: Any] = [
            "tx": totalTxBytes,
            "rx": totalRxBytes,
            "running": running,
            "stage": stage,
            "engine": engineStatus
        ]
        stateLock.unlock()
        completionHandler?(try? JSONSerialization.data(withJSONObject: reply))
    }

    private func stopReasonString(_ reason: NEProviderStopReason) -> String {
        switch reason {
        case .none: return "Обычное завершение"
        case .userInitiated: return "Пользователь остановил VPN"
        case .providerFailed: return "Сбой провайдера (providerFailed)"
        case .noNetworkAvailable: return "Сеть недоступна (noNetworkAvailable)"
        case .unrecoverableNetworkChange: return "Смена сети (unrecoverableNetworkChange)"
        case .providerDisabled: return "Конфигурация отключена (providerDisabled)"
        case .authenticationCanceled: return "Аутентификация отменена"
        case .configurationFailed: return "Ошибка конфигурации (configurationFailed)"
        case .idleTimeout: return "Таймаут неактивности (idleTimeout)"
        case .configurationDisabled: return "Профиль отключен (configurationDisabled)"
        case .configurationRemoved: return "Профиль удален (configurationRemoved)"
        case .superceded: return "Вытеснено другим VPN (superceded)"
        case .userLogout: return "Выход пользователя"
        case .userSwitch: return "Смена пользователя"
        case .connectionFailed: return "Сбой сетевого соединения (connectionFailed)"
        case .sleep: return "Переход устройства в сон (sleep)"
        case .appUpdate: return "Обновление приложения (appUpdate)"
        @unknown default: return "Код причины: \(reason.rawValue)"
        }
    }

    private static let protoIPv4 = NSNumber(value: AF_INET)
    private static let protoIPv6 = NSNumber(value: AF_INET6)

    private func readFromSystem() {
        guard isRunning else { return }
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self, self.isRunning else { return }
            autoreleasepool {
                var batchBytes: Int64 = 0
                for packet in packets {
                    try? self.engine.inject(packet)
                    batchBytes += Int64(packet.count)
                }
                if batchBytes > 0 {
                    self.stateLock.lock()
                    self.totalTxBytes += batchBytes
                    self.stateLock.unlock()
                }
            }
            self.readFromSystem()
        }
    }

    private func readFromEngine() {
        receiveQueue.async { [weak self] in
            guard let self else { return }
            var batchPackets: [Data] = []
            var batchProtocols: [NSNumber] = []
            batchPackets.reserveCapacity(64)
            batchProtocols.reserveCapacity(64)

            while self.isRunning {
                autoreleasepool {
                    let firstPacket: Data
                    do {
                        firstPacket = try self.engine.receive(timeoutMilliseconds: 500)
                    } catch {
                        // Сессия закрыта или сбой чтения: не крутим цикл вхолостую.
                        Thread.sleep(forTimeInterval: 0.1)
                        return
                    }
                    if firstPacket.isEmpty { return }

                    batchPackets.removeAll(keepingCapacity: true)
                    batchProtocols.removeAll(keepingCapacity: true)

                    let firstVer = firstPacket.first.map({ $0 >> 4 }) ?? 4
                    batchPackets.append(firstPacket)
                    batchProtocols.append(firstVer == 6 ? Self.protoIPv6 : Self.protoIPv4)
                    var rxBytes = Int64(firstPacket.count)

                    // Пакетная выборка без неограниченного буфера в памяти.
                    while batchPackets.count < 64 {
                        guard let nextPacket = try? self.engine.receive(timeoutMilliseconds: 0), !nextPacket.isEmpty else {
                            break
                        }
                        let ver = nextPacket.first.map({ $0 >> 4 }) ?? 4
                        batchPackets.append(nextPacket)
                        batchProtocols.append(ver == 6 ? Self.protoIPv6 : Self.protoIPv4)
                        rxBytes += Int64(nextPacket.count)
                    }

                    // writePackets не бросает исключений. При ENOBUFS и закрытом потоке пакеты просто теряются,
                    // TCP и QUIC их повторят. Короткая пауза даёт системе освободить буферы.
                    if !self.packetFlow.writePackets(batchPackets, withProtocols: batchProtocols) {
                        Thread.sleep(forTimeInterval: 0.002)
                    }

                    self.stateLock.lock()
                    self.totalRxBytes += rxBytes
                    self.stateLock.unlock()
                }
            }
        }
    }
}

private enum TunnelProviderError: LocalizedError {
    case missingConfiguration
    case missingFramework
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "Профиль Obsidian не содержит конфигурацию (configJson)."
        case .missingFramework: return "Добавьте Obsidian.xcframework в таргет PacketTunnel."
        case let .engine(message): return message
        }
    }
}

#if canImport(Obsidian)
/// Мост между gomobile StatusListener и замыканием. Протокол в Swift: MobileStatusListenerProtocol.
private final class EngineStatusListener: NSObject, MobileStatusListenerProtocol {
    private let handler: (String, String) -> Void

    init(handler: @escaping (String, String) -> Void) {
        self.handler = handler
        super.init()
    }

    func onStatusChange(_ status: String?, detail: String?) {
        handler(status ?? "", detail ?? "")
    }
}
#endif

private final class ObsidianPacketEngine {
    // sessionID читают packetFlow-колбэк, очередь приёма и stopTunnel одновременно: доступ только под замком.
    private let lock = NSLock()
    private var storedSessionID: String?
    #if canImport(Obsidian)
    private var listener: EngineStatusListener?
    #endif

    private var sessionID: String? {
        get { lock.lock(); defer { lock.unlock() }; return storedSessionID }
        set { lock.lock(); storedSessionID = newValue; lock.unlock() }
    }

    func start(configJson: String, mtu: Int, onStatus: @escaping (String, String) -> Void) throws {
        #if canImport(Obsidian)
        let statusListener = EngineStatusListener(handler: onStatus)
        listener = statusListener
        var error: NSError?
        let started: String? = MobileStartPacketTunnelWithConfig(configJson, mtu, nil, statusListener, nil, &error)
        if let error { throw TunnelProviderError.engine(error.localizedDescription) }
        guard let id = started, !id.isEmpty else { throw TunnelProviderError.engine("Ядро не вернуло идентификатор сессии.") }
        sessionID = id
        #else
        throw TunnelProviderError.missingFramework
        #endif
    }

    func inject(_ packet: Data) throws {
        #if canImport(Obsidian)
        guard let sessionID else { return }
        var error: NSError?
        MobileInjectPacket(sessionID, packet, &error)
        if let error { throw TunnelProviderError.engine(error.localizedDescription) }
        #endif
    }

    func receive(timeoutMilliseconds: Int) throws -> Data {
        #if canImport(Obsidian)
        guard let sessionID else { throw TunnelProviderError.engine("Сессия остановлена.") }
        var error: NSError?
        let packet = MobileReceivePacket(sessionID, timeoutMilliseconds, &error) ?? Data()
        if let error {
            // Таймаут ожидания пакета приходит из Go как context deadline exceeded: это пустой ответ, не сбой.
            if error.localizedDescription.contains("deadline exceeded") { return Data() }
            throw TunnelProviderError.engine(error.localizedDescription)
        }
        return packet
        #else
        return Data()
        #endif
    }

    func stop() {
        #if canImport(Obsidian)
        // Сначала снимаем идентификатор: параллельные inject и receive после этого сразу выходят.
        lock.lock()
        let id = storedSessionID
        storedSessionID = nil
        lock.unlock()
        guard let id else { return }
        var error: NSError?
        MobileStopTunnel(id, &error)
        listener = nil
        #endif
    }
}

// Лог пишут сразу несколько очередей (routeQueue, receiveQueue, колбэки ядра): без замка обновления теряются.
private let tunnelLogLock = NSLock()
private let tunnelLogFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

private func tunnelLog(_ message: String) {
    tunnelLogLock.lock()
    defer { tunnelLogLock.unlock() }
    let timestamp = tunnelLogFormatter.string(from: Date())
    let line = "[\(timestamp)] [Tunnel] \(message)"

    let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    let logsKey = "vpn.runtime.logs.v1"
    var logs = defaults.stringArray(forKey: logsKey) ?? []
    logs.append(line)
    if logs.count > 120 {
        logs.removeFirst(logs.count - 120)
    }
    defaults.set(logs, forKey: logsKey)
}
