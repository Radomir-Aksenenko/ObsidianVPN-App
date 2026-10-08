import Foundation
import Darwin

/// Итоговый набор маршрутов для NEPacketTunnelNetworkSettings.
struct SplitRoutePlan: Equatable {
    /// true: маршрут по умолчанию через туннель, excludedRoutes выводятся из туннеля.
    /// false: через туннель идут только includedRoutes.
    var useDefaultRoute: Bool
    var excludedRoutes: [IPv4Network]
    var includedRoutes: [IPv4Network]
    /// Домены для NEDNSSettings.matchDomains. [""] означает все запросы через туннельный DNS.
    var matchDomains: [String]
    /// Список обрезан по лимиту маршрутов.
    var truncated: Bool

    var routeCount: Int { useDefaultRoute ? excludedRoutes.count : includedRoutes.count }

    /// Отпечаток всех маршрутов. Если не изменился, повторно setTunnelNetworkSettings не нужен.
    var signature: String {
        let included = includedRoutes.map { $0.cidrString }.joined(separator: ",")
        let excluded = excludedRoutes.map { $0.cidrString }.joined(separator: ",")
        let domains = matchDomains.joined(separator: ",")
        return "\(useDefaultRoute)|\(included)|\(excluded)|\(domains)"
    }
}

/// Список маршрутов без дублей с ограничением по количеству.
private struct RouteList {
    private(set) var items: [IPv4Network] = []
    private(set) var truncated = false
    private var seen = Set<IPv4Network>()

    mutating func add(_ network: IPv4Network) {
        guard !seen.contains(network) else { return }
        guard items.count < SplitRouteBuilder.maxRoutes else {
            truncated = true
            return
        }
        seen.insert(network)
        items.append(network)
    }

    mutating func add(all networks: [IPv4Network]) {
        for network in networks { add(network) }
    }
}

/// Чистая логика без сети: собирает маршруты по режиму. Тестируется отдельно от NE.
enum SplitRouteBuilder {
    /// Лимит маршрутов на список. Нужен, чтобы уложиться в память Network Extension (около 15 МБ).
    static let maxRoutes = 2000
    static let tunnelDNSServers = ["1.1.1.1", "8.8.8.8"]

    static func plan(config: SplitTunnelConfig, serverIP: String?, resolvedIPs: [String]) -> SplitRoutePlan {
        let rules = config.rules
        let resolved = resolvedIPs.compactMap { IPv4Network.host($0) }
        let server = serverIP.flatMap { IPv4Network.host($0) }

        switch config.mode {
        case .off:
            var excluded = RouteList()
            if let server { excluded.add(server) }
            return SplitRoutePlan(
                useDefaultRoute: true,
                excludedRoutes: excluded.items,
                includedRoutes: [],
                matchDomains: [""],
                truncated: excluded.truncated
            )

        case .exclude:
            // Сервер VPN всегда исключен, иначе туннель сам себя заглушит.
            var excluded = RouteList()
            if let server { excluded.add(server) }
            excluded.add(all: rules.ipv4)
            excluded.add(all: resolved)
            return SplitRoutePlan(
                useDefaultRoute: true,
                excludedRoutes: excluded.items,
                includedRoutes: [],
                matchDomains: [""],
                truncated: excluded.truncated
            )

        case .include:
            // Без маршрута по умолчанию. DNS-серверы туннеля должны быть в маршрутах, иначе их запросы не дойдут.
            var included = RouteList()
            for dns in tunnelDNSServers {
                if let host = IPv4Network.host(dns) { included.add(host) }
            }
            included.add(all: rules.ipv4)
            included.add(all: resolved)
            let domains = rules.domains
            return SplitRoutePlan(
                useDefaultRoute: false,
                excludedRoutes: [],
                includedRoutes: included.items,
                matchDomains: domains.isEmpty ? [""] : domains,
                truncated: included.truncated
            )
        }
    }
}

/// Резолв доменов в IPv4 с общим таймаутом. Возвращает то, что успело ответить за таймаут.
enum DomainResolver {
    static func resolveIPv4(_ domains: [String], timeout: TimeInterval) -> [String] {
        guard !domains.isEmpty else { return [] }

        var hosts = Set<String>()
        for domain in domains {
            hosts.insert(domain)
            if !domain.hasPrefix("www.") {
                hosts.insert("www." + domain)
            }
        }

        let results = LookupResults()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .utility)
        for host in hosts {
            group.enter()
            queue.async {
                results.append(lookupIPv4(host))
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + timeout)
        return results.snapshot()
    }

    private static func lookupIPv4(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let head = result else { return [] }
        defer { freeaddrinfo(head) }

        var addresses: [String] = []
        var node: UnsafeMutablePointer<addrinfo>? = head
        while let current = node {
            if current.pointee.ai_family == AF_INET, let sockaddrPointer = current.pointee.ai_addr {
                sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var raw = sin.pointee.sin_addr
                    if inet_ntop(AF_INET, &raw, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                        addresses.append(String(cString: buffer))
                    }
                }
            }
            node = current.pointee.ai_next
        }
        return addresses
    }
}

private final class LookupResults {
    private let lock = NSLock()
    private var addresses = Set<String>()

    func append(_ found: [String]) {
        lock.lock()
        addresses.formUnion(found)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return addresses.sorted()
    }
}
