import Flutter
import UIKit
import NetworkExtension

/// Мост Flutter <-> NetworkExtension.
/// MethodChannel "obsidian/vpn", EventChannel "obsidian/vpn/events" (протокол в app-docs/ARCHITECTURE.md).
/// Все публичные методы и колбэки работают на главном потоке.
final class VpnChannel: NSObject, FlutterStreamHandler {
    private static let appGroupID = "group.com.obsidian.vpn"
    private static let errorKey = "lastTunnelError"

    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var sink: FlutterEventSink?
    private let defaults = UserDefaults(suiteName: VpnChannel.appGroupID) ?? .standard

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var lifecycleObservers: [NSObjectProtocol] = []

    private var statsTimer: Timer?
    private var stagePollTimer: Timer?
    private var statsWanted = false
    private var lastRx: Int64 = 0
    private var lastTx: Int64 = 0
    private var lastStatsAt: Date?

    private var lastStage = 1
    private var engineReconnecting = false
    private var userStopped = false
    private var sawActive = false
    private var reachedConnected = false
    private var lastPhase = ""

    private var providerBundleId: String {
        (Bundle.main.bundleIdentifier ?? "com.obsidian.vpn") + ".PacketTunnel"
    }

    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: "obsidian/vpn", binaryMessenger: messenger)
        eventChannel = FlutterEventChannel(name: "obsidian/vpn/events", binaryMessenger: messenger)
        super.init()

        methodChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.handle(call, result)
        }
        eventChannel.setStreamHandler(self)

        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopStatsTimer()
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.statsWanted else { return }
            self.startStatsTimer()
        })
    }

    deinit {
        stopStatsTimer()
        stopStagePoll()
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        events(statusMap(for: manager?.connection.status ?? .invalid, phaseOverride: nil, error: nil))
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    // MARK: - Method calls

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "prepare":
            prepare(result)
        case "connect":
            connect(call.arguments as? [String: Any], result)
        case "disconnect":
            disconnect(result)
        case "applySplit":
            applySplit(call.arguments as? [String: Any], result)
        case "setStatsActive":
            let active = (call.arguments as? [String: Any])?["active"] as? Bool ?? false
            setStatsActive(active)
            result(nil)
        case "currentStatus":
            loadManager(create: false) { [weak self] _, _ in
                guard let self else {
                    result(nil)
                    return
                }
                result(self.statusMap(for: self.manager?.connection.status ?? .invalid, phaseOverride: nil, error: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func prepare(_ result: @escaping FlutterResult) {
        loadManager(create: true) { [weak self] mgr, _ in
            guard let self, let mgr else {
                result(false)
                return
            }
            if mgr.protocolConfiguration == nil {
                mgr.protocolConfiguration = self.makeProtocol(serverAddress: "obsidian", providerConfiguration: [:], killSwitch: false)
            }
            mgr.localizedDescription = "Obsidian"
            mgr.isEnabled = true
            self.save(mgr) { error in
                result(error == nil)
            }
        }
    }

    private func connect(_ args: [String: Any]?, _ result: @escaping FlutterResult) {
        guard let args, let configJson = args["configJson"] as? String, !configJson.isEmpty else {
            result(FlutterError(code: "bad_args", message: "Не передана конфигурация (configJson).", details: nil))
            return
        }
        let profileId = args["profileId"] as? String ?? ""
        let name = args["name"] as? String ?? "Obsidian"
        let serverHost = args["serverHost"] as? String ?? ""
        let killSwitch = args["killSwitch"] as? Bool ?? false

        loadManager(create: true) { [weak self] mgr, error in
            guard let self, let mgr else {
                result(FlutterError(code: "load_failed", message: error?.localizedDescription ?? "Не удалось загрузить настройки VPN.", details: nil))
                return
            }
            let status = mgr.connection.status
            if status == .connected || status == .connecting || status == .reasserting {
                result(FlutterError(code: "busy", message: "VPN уже запущен.", details: nil))
                return
            }

            mgr.protocolConfiguration = self.makeProtocol(
                serverAddress: serverHost.isEmpty ? "obsidian" : serverHost,
                providerConfiguration: ["configJson": configJson, "profileId": profileId, "name": name],
                killSwitch: killSwitch
            )
            mgr.localizedDescription = "Obsidian"
            mgr.isEnabled = true

            self.defaults.removeObject(forKey: VpnChannel.errorKey)
            self.userStopped = false
            self.reachedConnected = false
            self.engineReconnecting = false
            self.lastStage = 1

            self.save(mgr) { saveError in
                if let saveError {
                    result(self.flutterError(for: saveError, fallback: "save_failed"))
                    return
                }
                do {
                    let options: [String: NSObject] = ["configJson": configJson as NSString]
                    try (mgr.connection as? NETunnelProviderSession)?.startVPNTunnel(options: options)
                    result(nil)
                } catch {
                    result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func disconnect(_ result: @escaping FlutterResult) {
        userStopped = true
        defaults.removeObject(forKey: VpnChannel.errorKey)
        manager?.connection.stopVPNTunnel()
        result(nil)
    }

    private func applySplit(_ args: [String: Any]?, _ result: @escaping FlutterResult) {
        guard let args, let configJson = args["configJson"] as? String, !configJson.isEmpty else {
            result(FlutterError(code: "bad_args", message: "Не передана конфигурация (configJson).", details: nil))
            return
        }
        guard let mgr = manager, let session = mgr.connection as? NETunnelProviderSession else {
            result(nil)
            return
        }
        let status = session.status
        guard status == .connected || status == .reasserting else {
            // Туннель не поднят: правила уйдут с ближайшим connect.
            result(nil)
            return
        }
        do {
            try session.sendProviderMessage(Data(configJson.utf8)) { reply in
                DispatchQueue.main.async {
                    if let reply, String(data: reply, encoding: .utf8) == "ok" {
                        result(nil)
                    } else {
                        result(FlutterError(code: "split_failed", message: "Не удалось применить раздельное туннелирование.", details: nil))
                    }
                }
            }
        } catch {
            result(FlutterError(code: "split_failed", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Manager

    private func makeProtocol(serverAddress: String, providerConfiguration: [String: Any], killSwitch: Bool) -> NETunnelProviderProtocol {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleId
        proto.serverAddress = serverAddress
        proto.providerConfiguration = providerConfiguration
        proto.disconnectOnSleep = false
        // Kill switch: весь трафик только через туннель, пока он поднят.
        proto.includeAllNetworks = killSwitch
        proto.excludeLocalNetworks = false
        return proto
    }

    private func loadManager(create: Bool, completion: @escaping (NETunnelProviderManager?, Error?) -> Void) {
        if let manager {
            completion(manager, nil)
            return
        }
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            DispatchQueue.main.async {
                guard let self else {
                    completion(nil, error)
                    return
                }
                if let error {
                    completion(nil, error)
                    return
                }
                let bundleId = self.providerBundleId
                let found = managers?.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleId
                }) ?? managers?.first
                if let found {
                    self.attach(found)
                    completion(found, nil)
                } else if create {
                    let fresh = NETunnelProviderManager()
                    self.attach(fresh)
                    completion(fresh, nil)
                } else {
                    completion(nil, nil)
                }
            }
        }
    }

    /// Сохраняет настройки и перечитывает их (без перечитывания startVPNTunnel может упасть на новом профиле).
    private func save(_ mgr: NETunnelProviderManager, completion: @escaping (Error?) -> Void) {
        mgr.saveToPreferences { error in
            if let error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            mgr.loadFromPreferences { loadError in
                DispatchQueue.main.async { completion(loadError) }
            }
        }
    }

    private func attach(_ mgr: NETunnelProviderManager) {
        manager = mgr
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: mgr.connection, queue: .main
        ) { [weak self] _ in
            self?.handleStatusChange()
        }
        handleStatusChange()
    }

    private func flutterError(for error: Error, fallback: String) -> FlutterError {
        let ns = error as NSError
        let denied = ns.domain == NEVPNErrorDomain && ns.code == NEVPNError.Code.configurationReadWriteFailed.rawValue
        return FlutterError(
            code: denied ? "permission_denied" : fallback,
            message: denied ? "Доступ к настройкам VPN не разрешён." : error.localizedDescription,
            details: nil
        )
    }

    // MARK: - Status

    private func handleStatusChange() {
        guard let status = manager?.connection.status else { return }
        var phaseOverride: String?
        var errorText: String?

        switch status {
        case .connecting, .reasserting:
            sawActive = true
            if status == .connecting { startStagePoll() }
        case .connected:
            sawActive = true
            reachedConnected = true
            stopStagePoll()
        case .disconnected, .invalid:
            stopStagePoll()
            stopStatsTimer()
            if sawActive {
                let stored = defaults.string(forKey: VpnChannel.errorKey)
                if let stored, !stored.isEmpty {
                    errorText = stored
                } else if !reachedConnected && !userStopped {
                    errorText = "Не удалось подключиться."
                }
                if errorText != nil { phaseOverride = "error" }
            }
            sawActive = false
            reachedConnected = false
            engineReconnecting = false
            lastStage = 1
        case .disconnecting:
            break
        @unknown default:
            break
        }

        let map = statusMap(for: status, phaseOverride: phaseOverride, error: errorText)
        let phase = map["phase"] as? String ?? ""
        let stage = map["stage"] as? Int ?? 0
        let signature = "\(phase)|\(stage)|\(errorText ?? "")"
        guard signature != lastPhase else { return }
        lastPhase = signature
        sink?(map)

        if statsWanted, status == .connected || status == .reasserting { startStatsTimer() }
    }

    private func statusMap(for status: NEVPNStatus, phaseOverride: String?, error: String?) -> [String: Any] {
        var phase = "disconnected"
        var stage = 0
        switch status {
        case .invalid, .disconnected:
            phase = "disconnected"
        case .connecting:
            phase = "connecting"
            stage = min(max(lastStage, 1), 3)
        case .connected:
            if engineReconnecting {
                phase = "reconnecting"
                stage = 3
            } else {
                phase = "connected"
                stage = 4
            }
        case .reasserting:
            phase = "reconnecting"
            stage = 3
        case .disconnecting:
            phase = "disconnecting"
        @unknown default:
            break
        }
        if let phaseOverride { phase = phaseOverride }

        var connectedAtMs: Any = NSNull()
        if phase == "connected" || phase == "reconnecting", let date = manager?.connection.connectedDate {
            connectedAtMs = Int(date.timeIntervalSince1970 * 1000)
        }
        return [
            "type": "status",
            "phase": phase,
            "stage": stage,
            "error": error ?? NSNull(),
            "connectedAtMs": connectedAtMs
        ]
    }

    // MARK: - Provider polling

    /// Во время подключения опрашиваем расширение каждые 0.5 с ради стадии рукопожатия. Потом таймер выключается.
    private func startStagePoll() {
        guard stagePollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollProvider(emitStats: false)
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        stagePollTimer = timer
        pollProvider(emitStats: false)
    }

    private func stopStagePoll() {
        stagePollTimer?.invalidate()
        stagePollTimer = nil
    }

    private func setStatsActive(_ active: Bool) {
        statsWanted = active
        if active {
            if UIApplication.shared.applicationState != .background { startStatsTimer() }
        } else {
            stopStatsTimer()
        }
    }

    private func startStatsTimer() {
        guard statsTimer == nil else { return }
        lastStatsAt = nil
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollProvider(emitStats: true)
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
        pollProvider(emitStats: true)
    }

    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
        lastStatsAt = nil
    }

    private func pollProvider(emitStats: Bool) {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        let status = session.status
        guard status == .connected || status == .connecting || status == .reasserting else { return }
        do {
            try session.sendProviderMessage(Data("stats".utf8)) { [weak self] reply in
                DispatchQueue.main.async {
                    guard let self, let reply,
                          let object = try? JSONSerialization.jsonObject(with: reply),
                          let dict = object as? [String: Any] else { return }
                    self.apply(reply: dict, emitStats: emitStats)
                }
            }
        } catch {
            // Расширение ещё не готово принимать сообщения: следующий тик повторит.
        }
    }

    private func apply(reply: [String: Any], emitStats: Bool) {
        let stage = (reply["stage"] as? NSNumber)?.intValue ?? lastStage
        let reconnecting = (reply["engine"] as? String) == "reconnecting"
        var changed = false
        if stage != lastStage { lastStage = stage; changed = true }
        if reconnecting != engineReconnecting { engineReconnecting = reconnecting; changed = true }
        if changed { handleStatusChange() }

        guard emitStats, statsTimer != nil, let sink else { return }
        let rx = (reply["rx"] as? NSNumber)?.int64Value ?? 0
        let tx = (reply["tx"] as? NSNumber)?.int64Value ?? 0
        let now = Date()
        var rxBps: Int64 = 0
        var txBps: Int64 = 0
        if let previous = lastStatsAt {
            let dt = now.timeIntervalSince(previous)
            if dt > 0.1 {
                rxBps = max(0, Int64(Double(rx - lastRx) / dt))
                txBps = max(0, Int64(Double(tx - lastTx) / dt))
            }
        }
        lastRx = rx
        lastTx = tx
        lastStatsAt = now
        sink(["type": "stats", "rx": rx, "tx": tx, "rxBps": rxBps, "txBps": txBps])
    }
}
