import Foundation
import Darwin

/// Итоговый набор маршрутов для NEPacketTunnelNetworkSettings (IPv4 и IPv6).
struct SplitRoutePlan: Equatable {
    /// true: маршрут по умолчанию (v4 и v6) через туннель, excluded-списки выводятся из туннеля.
    /// false: через туннель идут только included-списки (режим «только список»).
    var useDefaultRoute: Bool
    var excludedRoutes: [IPv4Network]
    var includedRoutes: [IPv4Network]
    var excludedRoutes6: [IPv6Network]
    var includedRoutes6: [IPv6Network]
    /// Домены для NEDNSSettings.matchDomains. [""] означает все запросы через туннельный DNS.
    var matchDomains: [String]
    /// Какой-либо список обрезан по лимиту маршрутов.
    var truncated: Bool

    var routeCount: Int { useDefaultRoute ? excludedRoutes.count : includedRoutes.count }
    var routeCount6: Int { useDefaultRoute ? excludedRoutes6.count : includedRoutes6.count }

    /// Отпечаток всех маршрутов. Если не изменился, повторный setTunnelNetworkSettings не нужен.
    var signature: String {
        let v4 = includedRoutes.map { $0.cidrString }.joined(separator: ",")
            + "|" + excludedRoutes.map { $0.cidrString }.joined(separator: ",")
        let v6 = includedRoutes6.map { $0.cidrString }.joined(separator: ",")
            + "|" + excludedRoutes6.map { $0.cidrString }.joined(separator: ",")
        return "\(useDefaultRoute)|\(v4)|\(v6)|\(matchDomains.joined(separator: ","))"
    }
}

/// Список маршрутов без дублей с ограничением по количеству (на каждый список отдельно).
private struct RouteList<Route: Hashable> {
    private(set) var items: [Route] = []
    private(set) var truncated = false
    private var seen = Set<Route>()

    mutating func add(_ route: Route) {
        guard !seen.contains(route) else { return }
        guard items.count < SplitRouteBuilder.maxRoutes else {
            truncated = true
            return
        }
        seen.insert(route)
        items.append(route)
    }

    mutating func add(all routes: [Route]) {
        for route in routes { add(route) }
    }
}

/// Чистая логика без сети: собирает маршруты по режиму. Не зависит от NetworkExtension.
enum SplitRouteBuilder {
    /// Лимит маршрутов на каждый список (отдельно для excluded и included, v4 и v6).
    /// Нужен, чтобы уложиться в память Network Extension (около 15 МБ).
    static let maxRoutes = 2000
    static let tunnelDNSServers = ["1.1.1.1", "8.8.8.8"]

    /// - Parameters:
    ///   - serverIP: IPv4 адрес VPN-сервера (исключается из туннеля в режимах с маршрутом по умолчанию).
    ///   - serverIPv6: IPv6 адрес сервера, если хост в ключе задан литералом.
    ///   - resolvedIPs: адреса, полученные при резолве доменов (смесь IPv4 и IPv6).
    static func plan(
        config: SplitTunnelConfig,
        serverIP: String?,
        serverIPv6: String?,
        resolvedIPs: [String]
    ) -> SplitRoutePlan {
        let rules = config.rules
        let resolved4 = resolvedIPs.compactMap { IPv4Network.host($0) }
        let resolved6 = resolvedIPs.compactMap { IPv6Network.host($0) }
        let server4 = serverIP.flatMap { IPv4Network.host($0) }
        let server6 = serverIPv6.flatMap { IPv6Network.host($0) }

        var excluded4 = RouteList<IPv4Network>()
        var included4 = RouteList<IPv4Network>()
        var excluded6 = RouteList<IPv6Network>()
        var included6 = RouteList<IPv6Network>()
        var useDefault = true
        var matchDomains = [""]

        switch config.mode {
        case .off:
            // Как раньше: весь трафик через VPN, сервер исключен. v6 - то же самое.
            if let server4 { excluded4.add(server4) }
            if let server6 { excluded6.add(server6) }

        case .exclude:
            // Сервер VPN всегда исключен, иначе туннель заглушит сам себя.
            if let server4 { excluded4.add(server4) }
            if let server6 { excluded6.add(server6) }
            excluded4.add(all: rules.ipv4)
            excluded4.add(all: resolved4)
            excluded6.add(all: rules.ipv6)
            excluded6.add(all: resolved6)

        case .include:
            // Без маршрута по умолчанию. DNS-серверы туннеля должны идти через него, иначе их запросы не дойдут.
            useDefault = false
            for dns in tunnelDNSServers {
                if let host = IPv4Network.host(dns) { included4.add(host) }
            }
            included4.add(all: rules.ipv4)
            included4.add(all: resolved4)
            included6.add(all: rules.ipv6)
            included6.add(all: resolved6)
            if !rules.domains.isEmpty {
                matchDomains = rules.domains
            }
        }

        return SplitRoutePlan(
            useDefaultRoute: useDefault,
            excludedRoutes: excluded4.items,
            includedRoutes: included4.items,
            excludedRoutes6: excluded6.items,
            includedRoutes6: included6.items,
            matchDomains: matchDomains,
            truncated: excluded4.truncated || included4.truncated || excluded6.truncated || included6.truncated
        )
    }
}

/// Резолв доменов в IPv4 и IPv6 (A и AAAA) с общим таймаутом.
/// Возвращает адреса, которые успели прийти за таймаут.
enum DomainResolver {
    static func resolve(_ domains: [String], timeout: TimeInterval) -> [String] {
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
        // Не больше 6 одновременных getaddrinfo: каждый блокирует поток, а памяти в расширении мало.
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 6
        queue.qualityOfService = .utility
        for host in hosts {
            group.enter()
            queue.addOperation {
                defer { group.leave() }
                // После таймаута оставшиеся имена не резолвим.
                if results.isClosed { return }
                results.append(lookupAddresses(host))
            }
        }
        _ = group.wait(timeout: .now() + timeout)
        results.close()
        return results.snapshot()
    }

    /// AF_UNSPEC возвращает и A, и AAAA записи. Текст адреса получаем через getnameinfo,
    /// без приведения указателей к sockaddr_in и sockaddr_in6.
    private static func lookupAddresses(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>? = nil
        guard getaddrinfo(host, nil, &hints, &result) == 0, let head = result else { return [] }
        defer { freeaddrinfo(head) }

        var addresses: [String] = []
        var node: UnsafeMutablePointer<addrinfo>? = head
        while let current = node {
            if let address = current.pointee.ai_addr {
                var buffer = [CChar](repeating: 0, count: 1025)
                let status = getnameinfo(
                    address,
                    current.pointee.ai_addrlen,
                    &buffer,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if status == 0 {
                    addresses.append(String(cString: buffer))
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
    private var closed = false

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    /// После закрытия поздние ответы не попадают в результат.
    func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }

    func append(_ found: [String]) {
        lock.lock()
        if !closed { addresses.formUnion(found) }
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return addresses.sorted()
    }
}
