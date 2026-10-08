import Foundation
import Darwin

// Раздельное туннелирование для одного профиля.
// Ключи JSON совпадают с desktop-профилем (split_tunnel_mode, split_sites), см. desktop/src/main.js.
// Файл общий для приложения и Network Extension: здесь только данные и разбор, без сетевых вызовов.

enum SplitTunnelMode: String, Codable, CaseIterable, Sendable {
    /// Раздельного туннелирования нет: весь трафик идет через VPN.
    case off
    /// Через VPN идет только трафик к перечисленным сайтам и адресам.
    case include
    /// Через VPN идет весь трафик, кроме перечисленных сайтов и адресов.
    case exclude

    /// Разбирает значение режима, в том числе алиасы из Go-ядра (core/cmd/client/split_tunnel.go).
    static func parse(_ raw: String) -> SplitTunnelMode? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "off", "none":
            return .off
        case "include", "only", "only_selected", "vpn_only":
            return .include
        case "exclude", "except", "all_except", "bypass_selected":
            return .exclude
        default:
            return nil
        }
    }
}

/// Готовые наборы правил. Содержимое - в SplitPresets.swift.
enum SplitPreset: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case telegram
    case youtube
    case russianServices = "ru"
    case localNetwork = "local"

    var id: String { rawValue }
}

/// Правило раздельного туннелирования после разбора строки.
enum SplitRule: Equatable, Hashable, Sendable {
    case ipv4(IPv4Network)
    /// IPv6-адрес или префикс. Идет в маршруты v6 вместе с IPv4-правилами.
    case ipv6(IPv6Network)
    case domain(String)

    /// Каноническая запись, которая попадает в список и в JSON.
    var canonical: String {
        switch self {
        case let .ipv4(network): return network.cidrString
        case let .ipv6(network): return network.cidrString
        case let .domain(name): return name
        }
    }
}

struct SplitRuleError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

/// Одна строка, которую не удалось принять, и причина для показа пользователю.
struct SplitRuleIssue: Equatable, Sendable {
    let input: String
    let reason: String
}

struct IPv4Network: Hashable, Sendable {
    /// Адрес сети в порядке байтов хоста.
    let address: UInt32
    let prefix: Int

    init(address: UInt32, prefix: Int) {
        let clamped = min(max(prefix, 0), 32)
        self.prefix = clamped
        self.address = address & IPv4Network.mask(for: clamped)
    }

    static func mask(for prefix: Int) -> UInt32 {
        prefix <= 0 ? 0 : UInt32.max << (32 - prefix)
    }

    /// Разбирает dotted-quad. Сокращенная запись вида 10.1 не принимается.
    static func parseAddress(_ text: String) -> UInt32? {
        var addr = in_addr()
        guard text.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)
    }

    static func host(_ text: String) -> IPv4Network? {
        guard let value = parseAddress(text) else { return nil }
        return IPv4Network(address: value, prefix: 32)
    }

    var mask: UInt32 { IPv4Network.mask(for: prefix) }

    var addressString: String { IPv4Network.dotted(address) }

    var maskString: String { IPv4Network.dotted(mask) }

    var cidrString: String {
        prefix == 32 ? addressString : "\(addressString)/\(prefix)"
    }

    static func dotted(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}

struct IPv6Network: Hashable, Sendable {
    /// Адрес сети: 16 байт, биты за пределами префикса обнулены.
    let bytes: [UInt8]
    let prefix: Int

    init(bytes: [UInt8], prefix: Int) {
        let clamped = min(max(prefix, 0), 128)
        var masked = bytes
        for index in 0..<min(16, masked.count) {
            let bitsKept = clamped - index * 8
            let keep: UInt8
            if bitsKept >= 8 {
                keep = 0xFF
            } else if bitsKept <= 0 {
                keep = 0
            } else {
                keep = UInt8(truncatingIfNeeded: 0xFF << (8 - bitsKept))
            }
            masked[index] &= keep
        }
        self.bytes = masked
        self.prefix = clamped
    }

    /// Разбирает IPv6-адрес (без маски) в 16 байт.
    static func parseAddress(_ text: String) -> [UInt8]? {
        var addr = in6_addr()
        guard text.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }

    /// Адрес как одиночный хост (/128).
    static func host(_ text: String) -> IPv6Network? {
        guard let bytes = parseAddress(text) else { return nil }
        return IPv6Network(bytes: bytes, prefix: 128)
    }

    var addressString: String {
        var raw = in6_addr()
        withUnsafeMutableBytes(of: &raw) { dest in
            for index in 0..<min(16, bytes.count) {
                dest[index] = bytes[index]
            }
        }
        var buffer = [CChar](repeating: 0, count: 64)
        guard inet_ntop(AF_INET6, &raw, &buffer, 64) != nil else { return "::" }
        return String(cString: buffer)
    }

    var cidrString: String {
        prefix == 128 ? addressString : "\(addressString)/\(prefix)"
    }
}

/// Все правила (пользовательские и из наборов) в разобранном виде.
struct SplitRules: Equatable, Sendable {
    var ipv4: [IPv4Network] = []
    var ipv6: [IPv6Network] = []
    var domains: [String] = []

    var isEmpty: Bool { ipv4.isEmpty && ipv6.isEmpty && domains.isEmpty }

    static func build(from raws: [String]) -> SplitRules {
        var rules = SplitRules()
        var seenV4 = Set<IPv4Network>()
        var seenV6 = Set<IPv6Network>()
        var seenDomains = Set<String>()

        for raw in raws {
            guard let rule = try? SplitRuleParser.parse(raw) else { continue }
            switch rule {
            case let .ipv4(network):
                if seenV4.insert(network).inserted { rules.ipv4.append(network) }
            case let .ipv6(network):
                if seenV6.insert(network).inserted { rules.ipv6.append(network) }
            case let .domain(name):
                if seenDomains.insert(name).inserted { rules.domains.append(name) }
            }
        }
        return rules
    }
}

struct SplitTunnelConfig: Equatable, Hashable, Sendable {
    var mode: SplitTunnelMode = .off
    /// Пользовательские строки: домены, IP или CIDR. Хранятся в каноническом виде.
    var entries: [String] = []
    var presets: Set<SplitPreset> = []

    /// Количество пунктов для короткой подписи: строки плюс выбранные наборы.
    var itemCount: Int { entries.count + presets.count }

    /// Все строки правил: пользовательские и из выбранных наборов в фиксированном порядке.
    var allRuleStrings: [String] {
        entries + SplitPreset.allCases.filter { presets.contains($0) }.flatMap { SplitPresets.entries(for: $0) }
    }

    var rules: SplitRules { SplitRules.build(from: allRuleStrings) }

    var jsonData: Data? { try? JSONEncoder().encode(self) }

    var jsonString: String {
        guard let data = jsonData, let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    static func decode(json data: Data) -> SplitTunnelConfig? {
        try? JSONDecoder().decode(SplitTunnelConfig.self, from: data)
    }

    /// Разбирает строки, введенные пользователем или пришедшие в ссылке.
    /// Принятые строки приводятся к каноническому виду и не дублируются.
    static func canonicalize(_ raws: [String]) -> (accepted: [String], issues: [SplitRuleIssue]) {
        var accepted: [String] = []
        var issues: [SplitRuleIssue] = []
        for raw in raws {
            do {
                guard let rule = try SplitRuleParser.parse(raw) else { continue }
                let text = rule.canonical
                if !accepted.contains(text) { accepted.append(text) }
            } catch let error as SplitRuleError {
                issues.append(SplitRuleIssue(input: raw, reason: error.message))
            } catch {
                issues.append(SplitRuleIssue(input: raw, reason: "неверный формат"))
            }
        }
        return (accepted, issues)
    }

    /// Импорт из параметров ссылки или JSON. Строки списка могут быть через запятую или массивом.
    /// Возвращает nil, если в данных нет полей раздельного туннелирования.
    static func imported(from fields: [String: Any]) -> SplitTunnelConfig? {
        let modeRaw = fields["split_tunnel_mode"] as? String
        let sites = stringList(fields["split_sites"])
        let legacy = stringList(fields["route_ips"])
        guard modeRaw != nil || !sites.isEmpty || !legacy.isEmpty else { return nil }

        let source = sites.isEmpty ? legacy : sites
        let entries = canonicalize(source).accepted

        let mode: SplitTunnelMode
        if let modeRaw, let parsed = SplitTunnelMode.parse(modeRaw) {
            mode = parsed
        } else if sites.isEmpty && !legacy.isEmpty {
            // route_ips без режима: так же трактует Go-ядро.
            mode = .include
        } else {
            // Режим не задан: как в desktop, исключения.
            mode = entries.isEmpty ? .off : .exclude
        }
        return SplitTunnelConfig(mode: mode, entries: entries, presets: [])
    }

    private static func stringList(_ value: Any?) -> [String] {
        let raw: [String]
        if let list = value as? [String] {
            raw = list
        } else if let text = value as? String {
            raw = text.components(separatedBy: CharacterSet(charactersIn: ",;\n\r\t "))
        } else {
            raw = []
        }
        return raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

extension SplitTunnelConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case mode = "split_tunnel_mode"
        case entries = "split_sites"
        case presets = "split_presets"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawMode = try container.decodeIfPresent(String.self, forKey: .mode)
        mode = rawMode.flatMap { SplitTunnelMode.parse($0) } ?? .off
        entries = try container.decodeIfPresent([String].self, forKey: .entries) ?? []
        let rawPresets = try container.decodeIfPresent([String].self, forKey: .presets) ?? []
        // Неизвестные наборы из будущих версий пропускаем, а не ломаем профиль целиком.
        presets = Set(rawPresets.compactMap { SplitPreset(rawValue: $0) })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode.rawValue, forKey: .mode)
        try container.encode(entries, forKey: .entries)
        try container.encode(presets.map { $0.rawValue }.sorted(), forKey: .presets)
    }
}

enum SplitRuleParser {
    /// Разбирает одну строку. Возвращает nil для пустой строки и комментария (#).
    static func parse(_ raw: String) throws -> SplitRule? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, !value.hasPrefix("#") else { return nil }

        if let slash = value.firstIndex(of: "/"), !value.contains("://") {
            let addressPart = String(value[..<slash])
            let prefixPart = String(value[value.index(after: slash)...])
            guard let prefix = Int(prefixPart) else {
                throw SplitRuleError(message: "«\(raw)»: неверная маска подсети")
            }
            if let address = IPv4Network.parseAddress(addressPart) {
                guard (0...32).contains(prefix) else {
                    throw SplitRuleError(message: "«\(raw)»: маска IPv4 должна быть от 0 до 32")
                }
                return .ipv4(IPv4Network(address: address, prefix: prefix))
            }
            if let bytes = IPv6Network.parseAddress(addressPart) {
                guard (0...128).contains(prefix) else {
                    throw SplitRuleError(message: "«\(raw)»: маска IPv6 должна быть от 0 до 128")
                }
                return .ipv6(IPv6Network(bytes: bytes, prefix: prefix))
            }
            throw SplitRuleError(message: "«\(raw)»: неверный адрес подсети")
        }

        if let bytes = IPv6Network.parseAddress(value) {
            return .ipv6(IPv6Network(bytes: bytes, prefix: 128))
        }

        // Ссылки и адреса с портом: оставляем только имя хоста.
        var host = value
        if let range = host.range(of: "://") {
            host = String(host[range.upperBound...])
        }
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        if let address = IPv4Network.parseAddress(host) {
            return .ipv4(IPv4Network(address: address, prefix: 32))
        }

        if host.contains("*") {
            throw SplitRuleError(message: "«\(raw)»: маски вроде *.ru на iOS не работают, добавьте сайты по одному")
        }
        guard !host.isEmpty, host.count <= 253 else {
            throw SplitRuleError(message: "«\(raw)»: неверный адрес или домен")
        }
        if host.contains(where: { !$0.isASCII }) {
            throw SplitRuleError(message: "«\(raw)»: кириллические домены пока не поддерживаются, укажите вариант xn--")
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ isValidDomainLabel($0) }) else {
            throw SplitRuleError(message: "«\(raw)»: неверный адрес или домен")
        }
        // Зона верхнего уровня не может быть числом: так отсекаем записи вроде 1.2.3.999 без IPv4-разбора.
        if let tld = labels.last, tld.allSatisfy({ $0.isNumber }) {
            throw SplitRuleError(message: "«\(raw)»: неверный адрес или домен")
        }
        return .domain(host)
    }

    private static func isValidDomainLabel(_ label: Substring) -> Bool {
        guard (1...63).contains(label.count) else { return false }
        guard label.first != "-", label.last != "-" else { return false }
        return label.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
        }
    }

}
