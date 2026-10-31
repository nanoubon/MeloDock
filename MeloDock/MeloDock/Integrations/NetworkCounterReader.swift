import Darwin
import Foundation

protocol NetworkCounterReading {
    /// Cumulative counters for each physical interface, keyed by BSD name. Empty when the system call fails.
    func read() -> [String: NetworkCounters]
}

/// Reads per-interface byte counters with `getifaddrs`, which the App Sandbox allows without an entitlement.
struct SystemNetworkCounterReader: NetworkCounterReading {
    /// Only Ethernet and Wi-Fi (`en*`). Tunnels (`utun*`), AirDrop (`awdl*`, `llw*`) and bridges re-carry the same
    /// traffic, so counting them would double it under a VPN or Internet Sharing.
    static func isPhysical(_ name: String) -> Bool {
        let suffix = name.dropFirst(2)
        return name.hasPrefix("en") && !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    func read() -> [String: NetworkCounters] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var counters: [String: NetworkCounters] = [:]
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let item = entry.pointee
            let flags = Int32(item.ifa_flags)
            // The link-layer entry is the one that carries the byte counters (one per interface).
            guard let address = item.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let data = item.ifa_data else { continue }
            let name = String(cString: item.ifa_name)
            guard Self.isPhysical(name) else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = NetworkCounters(received: stats.ifi_ibytes, sent: stats.ifi_obytes)
        }
        return counters
    }
}
