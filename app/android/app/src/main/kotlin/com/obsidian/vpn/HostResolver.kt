package com.obsidian.vpn

import java.net.Inet4Address
import java.net.InetAddress
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

/**
 * Resolves host names to IPv4 addresses inside one shared time budget. Hosts that do not answer
 * in time are left out of the result. Never throws. Must not run on the main thread.
 */
internal object HostResolver {
    private const val MAX_THREADS = 8

    fun resolve(hosts: Collection<String>, budgetMs: Long): Map<String, List<Ipv4Cidr>> {
        val names = hosts.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        if (names.isEmpty()) return emptyMap()

        val pool = Executors.newFixedThreadPool(minOf(names.size, MAX_THREADS)) { runnable ->
            Thread(runnable, "obsidian-dns").apply { isDaemon = true }
        }
        try {
            val deadline = System.nanoTime() + budgetMs * 1_000_000L
            val futures: Map<String, Future<List<Ipv4Cidr>>> = names.associateWith { name ->
                pool.submit(Callable { lookupV4(name) })
            }
            val result = HashMap<String, List<Ipv4Cidr>>()
            for ((name, future) in futures) {
                val remainingNs = deadline - System.nanoTime()
                if (remainingNs <= 0L) {
                    future.cancel(true)
                    continue
                }
                try {
                    result[name] = future.get(remainingNs, TimeUnit.NANOSECONDS)
                } catch (e: Exception) {
                    // Unknown host, timeout or interruption: this name is simply not routed.
                    future.cancel(true)
                }
            }
            return result
        } finally {
            pool.shutdownNow()
        }
    }

    private fun lookupV4(name: String): List<Ipv4Cidr> =
        InetAddress.getAllByName(name).mapNotNull { address ->
            (address as? Inet4Address)?.let { Ipv4Cidr(Ipv4.fromBytes(it.address), 32) }
        }
}
