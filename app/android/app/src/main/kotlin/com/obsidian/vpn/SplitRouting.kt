package com.obsidian.vpn

/**
 * IPv4 network. [network] is the masked base address packed into a Long (host byte order),
 * [prefix] is 0..32.
 */
internal data class Ipv4Cidr(val network: Long, val prefix: Int) {
    val first: Long
        get() = network

    val last: Long
        get() = network + (1L shl (32 - prefix)) - 1L
}

/** Pure IPv4 helpers. No Android imports, so this file can be unit tested on a plain JVM. */
internal object Ipv4 {
    const val MAX: Long = 0xFFFFFFFFL

    val ANY = Ipv4Cidr(0L, 0)

    private val DOTTED = Regex("""\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?""")

    /** Parses "a.b.c.d" into a packed Long, or returns null. */
    fun parseAddress(text: String): Long? {
        val parts = text.split('.')
        if (parts.size != 4) return null
        var value = 0L
        for (part in parts) {
            if (part.isEmpty() || part.length > 3 || !part.all { it in '0'..'9' }) return null
            val octet = part.toInt()
            if (octet > 255) return null
            value = (value shl 8) or octet.toLong()
        }
        return value
    }

    /** Parses "a.b.c.d" (as /32) or "a.b.c.d/n". Host bits are masked off. */
    fun parseCidr(text: String): Ipv4Cidr? {
        val slash = text.indexOf('/')
        if (slash < 0) {
            val address = parseAddress(text) ?: return null
            return cidr(address, 32)
        }
        val address = parseAddress(text.substring(0, slash)) ?: return null
        val prefix = text.substring(slash + 1).toIntOrNull() ?: return null
        if (prefix !in 0..32) return null
        return cidr(address, prefix)
    }

    /** True when the whole string is shaped like a dotted IPv4 literal, optionally with /n. */
    fun isDottedLiteral(text: String): Boolean = DOTTED.matches(text)

    fun cidr(address: Long, prefix: Int): Ipv4Cidr {
        val mask = (MAX shl (32 - prefix)) and MAX
        return Ipv4Cidr(address and mask, prefix)
    }

    fun fromBytes(bytes: ByteArray): Long =
        bytes.fold(0L) { acc, b -> (acc shl 8) or (b.toLong() and 0xFFL) }

    fun format(address: Long): String =
        listOf(24, 16, 8, 0).joinToString(".") { shift -> ((address shr shift) and 0xFFL).toString() }

    /**
     * Every IPv4 address except the given networks, as a minimal list of CIDR blocks.
     * Used below API 33, where VpnService.Builder.excludeRoute does not exist.
     */
    fun complement(excludes: List<Ipv4Cidr>): List<Ipv4Cidr> {
        val sorted = excludes.map { it.first to it.last }.sortedBy { it.first }
        val merged = ArrayList<Pair<Long, Long>>()
        for ((start, end) in sorted) {
            val previous = merged.lastOrNull()
            if (previous != null && start <= previous.second + 1L) {
                merged[merged.size - 1] = previous.first to maxOf(previous.second, end)
            } else {
                merged.add(start to end)
            }
        }
        val out = ArrayList<Ipv4Cidr>()
        var cursor = 0L
        for ((start, end) in merged) {
            if (start > cursor) appendRange(out, cursor, start - 1L)
            cursor = end + 1L
        }
        if (cursor <= MAX) appendRange(out, cursor, MAX)
        return out
    }

    /** Splits the inclusive range [from, to] into the fewest aligned CIDR blocks. */
    private fun appendRange(out: MutableList<Ipv4Cidr>, from: Long, to: Long) {
        var lo = from
        while (lo <= to) {
            var hostBits = 0
            while (hostBits < 32) {
                val next = hostBits + 1
                val size = 1L shl next
                val aligned = (lo and (size - 1L)) == 0L
                val fits = lo + size - 1L <= to
                if (!aligned || !fits) break
                hostBits = next
            }
            out.add(Ipv4Cidr(lo, 32 - hostBits))
            lo += 1L shl hostBits
        }
    }
}

/** IPv6 network. [address] is the masked canonical literal (as InetAddress prints it), [prefix] is 1..128. */
internal data class Ipv6Cidr(val address: String, val prefix: Int)

/** IPv6 literal helpers. Literals only: no DNS lookups, and the input must contain at least two colons. */
internal object Ipv6 {
    private val LITERAL = Regex("""[0-9a-fA-F:]+(\.\d{1,3}){0,3}(/\d{1,3})?""")

    /** Parses "addr" (as /128) or "addr/n". Host bits are masked off. Returns null if unusable. */
    fun parseCidr(text: String): Ipv6Cidr? {
        if (!LITERAL.matches(text) || text.count { it == ':' } < 2) return null
        val slash = text.indexOf('/')
        val prefix = if (slash < 0) 128 else (text.substring(slash + 1).toIntOrNull() ?: return null)
        if (prefix !in 1..128) return null
        val addressText = if (slash < 0) text else text.substring(0, slash)
        val raw = try {
            java.net.InetAddress.getByName(addressText).address
        } catch (e: java.net.UnknownHostException) {
            return null
        }
        if (raw.size != 16) return null
        val masked = ByteArray(16) { i ->
            val bits = prefix - i * 8
            when {
                bits >= 8 -> raw[i]
                bits <= 0 -> 0.toByte()
                else -> (raw[i].toInt() and (0xFF shl (8 - bits))).toByte()
            }
        }
        return Ipv6Cidr(java.net.InetAddress.getByAddress(masked).hostAddress.orEmpty(), prefix)
    }
}

/** Split tunnel mode, resolved the same way as core/cmd/client/split_tunnel.go. */
internal enum class SplitMode { OFF, INCLUDE, EXCLUDE }

/** Routes to add to the VPN interface. [includes] is used in INCLUDE, [excludes] otherwise. */
internal class RoutePlan(
    val mode: SplitMode,
    val includes: List<Ipv4Cidr>,
    val excludes: List<Ipv4Cidr>,
)

internal object SplitRules {
    private val OFF_ALIASES = setOf("off", "none", "disabled")
    private val INCLUDE_ALIASES = setOf("include", "only", "only_selected", "vpn_only")
    private val EXCLUDE_ALIASES = setOf("exclude", "except", "all_except", "bypass_selected")

    /**
     * No entries means full tunnel. An explicit mode wins. Otherwise the mode is inferred the
     * way the Go client does it: route_ips present means include, else exclude.
     */
    fun mode(raw: String, hasEntries: Boolean, hasRouteIps: Boolean): SplitMode {
        val value = raw.trim().lowercase()
        return when {
            value in OFF_ALIASES || !hasEntries -> SplitMode.OFF
            value in INCLUDE_ALIASES -> SplitMode.INCLUDE
            value in EXCLUDE_ALIASES -> SplitMode.EXCLUDE
            hasRouteIps -> SplitMode.INCLUDE
            else -> SplitMode.EXCLUDE
        }
    }

    class Parsed(
        val cidrs: List<Ipv4Cidr>,
        val domains: List<String>,
        /** Entries that cannot be turned into routes: wildcards, bare TLDs, junk, ::/0. */
        val skipped: Int,
        val cidrs6: List<Ipv6Cidr> = emptyList(),
    )

    /**
     * Splits raw entries into IPv4 networks and host names. Host names are resolved later.
     * "*.example.com" resolves only the apex "example.com" on Android (subdomains are not expanded).
     */
    fun parse(entries: List<String>): Parsed {
        val cidrs = LinkedHashSet<Ipv4Cidr>()
        val cidrs6 = LinkedHashSet<Ipv6Cidr>()
        val domains = LinkedHashSet<String>()
        var skipped = 0
        for (raw in entries) {
            val item = raw.trim()
            if (item.isEmpty() || item.startsWith("#")) continue
            if (Ipv4.isDottedLiteral(item)) {
                val network = Ipv4.parseCidr(item)
                if (network != null && network.prefix > 0) {
                    cidrs.add(network)
                } else {
                    skipped++
                }
                continue
            }
            // Two or more colons means an IPv6 literal. One colon is host:port and is stripped below.
            if (item.count { it == ':' } >= 2) {
                val network = Ipv6.parseCidr(item)
                if (network != null) cidrs6.add(network) else skipped++
                continue
            }
            val domain = normalizeDomain(item)
            if (domain == null) {
                skipped++
            } else {
                domains.add(domain)
            }
        }
        return Parsed(cidrs.toList(), domains.toList(), skipped, cidrs6.toList())
    }

    /** Lowercase host name without scheme, path, port, wildcard or trailing dot. Null if unusable. */
    fun normalizeDomain(raw: String): String? {
        var host = raw.trim().lowercase()
        host = host.removePrefix("https://").removePrefix("http://")
        host = host.substringBefore('/').substringBefore('?').substringBefore('#').substringBefore(':')
        host = host.trimEnd('.').removePrefix("*.").removePrefix(".")
        if (host.isEmpty() || '*' in host || '.' !in host) return null
        val ascii = try {
            java.net.IDN.toASCII(host)
        } catch (e: IllegalArgumentException) {
            return null
        }
        val valid = ascii.all { it.code < 128 && (it.isLetterOrDigit() || it == '-' || it == '.') }
        return if (valid) ascii else null
    }

    /**
     * Builds the route set.
     * - INCLUDE: only the listed networks, resolved domains and the DNS servers go to the tunnel.
     * - EXCLUDE: everything except the listed networks and resolved domains.
     * - OFF: everything.
     * The server address is always excluded in EXCLUDE and OFF, so the tunnel's own traffic
     * never loops back into the tunnel. The Go socket protector is the primary guard for this.
     */
    fun plan(
        mode: SplitMode,
        userCidrs: List<Ipv4Cidr>,
        domainAddrs: List<Ipv4Cidr>,
        serverAddrs: List<Ipv4Cidr>,
        dnsAddrs: List<Ipv4Cidr>,
    ): RoutePlan = when (mode) {
        SplitMode.INCLUDE -> RoutePlan(mode, (userCidrs + domainAddrs + dnsAddrs).distinct(), emptyList())
        SplitMode.EXCLUDE -> RoutePlan(mode, listOf(Ipv4.ANY), (serverAddrs + userCidrs + domainAddrs).distinct())
        SplitMode.OFF -> RoutePlan(mode, listOf(Ipv4.ANY), serverAddrs.distinct())
    }
}
