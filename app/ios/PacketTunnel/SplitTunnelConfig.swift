import Foundation
import Darwin

// Раздельное туннелирование: модель и разбор правил. Ключи JSON: split_tunnel_mode, split_sites, split_presets.
// Файл входит только в таргет PacketTunnel, сетевых вызовов здесь нет.

enum SplitTunnelMode: String {
    case off
    case include
    case exclude

    /// Разбирает значение режима, в том числе алиасы из Go-ядра.
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

enum SplitPreset: String, CaseIterable {
    case telegram
    case youtube
    case russianServices = "ru"
    case localNetwork = "local"
}

enum SplitRule: Equatable, Hashable {
    case ipv4(IPv4Network)
    case ipv6(IPv6Network)
    case domain(String)
}

struct SplitRuleError: Error {
    let message: String
}

struct IPv4Network: Hashable {
    let address: UInt32
    let prefix: Int

    init(address: UInt32, prefix: Int) {
        let clamped = min(max(prefix, 0), 32)
        self.prefix = clamped
        self.address = address & IPv4Network.mask(for: clamped)
    }

    static func mask(for prefix: Int) -> UInt32 {
        prefix <= 0 ? 0 : UInt32.max << UInt32(32 - prefix)
    }

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

struct IPv6Network: Hashable {
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

    static func parseAddress(_ text: String) -> [UInt8]? {
        var addr = in6_addr()
        guard text.withCString({ inet_pton(AF_INET6, $0, &addr) }) == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }

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

struct SplitRules: Equatable {
    var ipv4: [IPv4Network] = []
    var ipv6: [IPv6Network] = []
    var domains: [String] = []

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

struct SplitTunnelConfig: Equatable {
    var mode: SplitTunnelMode = .off
    var entries: [String] = []
    var presets: Set<SplitPreset> = []

    var allRuleStrings: [String] {
        entries + SplitPreset.allCases.filter { presets.contains($0) }.flatMap { SplitPresets.entries(for: $0) }
    }

    var rules: SplitRules { SplitRules.build(from: allRuleStrings) }

    /// Читает поля из JSON (полный ClientConfig или только split-поля). nil, если это не JSON-объект.
    static func decode(json data: Data) -> SplitTunnelConfig? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let fields = object as? [String: Any] else { return nil }
        var config = SplitTunnelConfig()
        if let raw = fields["split_tunnel_mode"] as? String, let mode = SplitTunnelMode.parse(raw) {
            config.mode = mode
        }
        config.entries = stringList(fields["split_sites"])
        // Неизвестные наборы из будущих версий пропускаем.
        config.presets = Set(stringList(fields["split_presets"]).compactMap { SplitPreset(rawValue: $0) })
        return config
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

enum SplitRuleParser {
    /// Разбирает одну строку. Возвращает nil для пустой строки и комментария (#).
    static func parse(_ raw: String) throws -> SplitRule? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, !value.hasPrefix("#") else { return nil }

        if let slash = value.firstIndex(of: "/"), !value.contains("://") {
            let addressPart = String(value[..<slash])
            let prefixPart = String(value[value.index(after: slash)...])
            guard let prefix = Int(prefixPart) else {
                throw SplitRuleError(message: "bad prefix")
            }
            if let address = IPv4Network.parseAddress(addressPart) {
                guard (0...32).contains(prefix) else { throw SplitRuleError(message: "bad v4 prefix") }
                return .ipv4(IPv4Network(address: address, prefix: prefix))
            }
            if let bytes = IPv6Network.parseAddress(addressPart) {
                guard (0...128).contains(prefix) else { throw SplitRuleError(message: "bad v6 prefix") }
                return .ipv6(IPv6Network(bytes: bytes, prefix: prefix))
            }
            throw SplitRuleError(message: "bad address")
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

        if host.contains("*") { throw SplitRuleError(message: "wildcard") }
        guard !host.isEmpty, host.count <= 253 else { throw SplitRuleError(message: "bad host") }
        if host.contains(where: { !$0.isASCII }) { throw SplitRuleError(message: "non-ascii host") }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ isValidDomainLabel($0) }) else {
            throw SplitRuleError(message: "bad host")
        }
        if let tld = labels.last, tld.allSatisfy({ $0.isNumber }) {
            throw SplitRuleError(message: "bad host")
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
