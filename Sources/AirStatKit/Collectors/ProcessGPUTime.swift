import Foundation
import IOKit

/// Each process's share of the GPU, from the GPU's own accounting.
///
/// A process that draws with Metal opens user clients on the GPU's accelerator, and each
/// client keeps the GPU time it has used, in nanoseconds, under "AppUsage". The registry
/// publishes them for every process, other users' as well, and to a sandboxed app too,
/// in about two milliseconds. Summed over an interval they come to the device
/// utilisation `GPUCollector` reports, so the shares are the GPU's figures, not a guess.
///
/// Runs on `SamplingCore`'s serial queue, as part of `ProcessCollector`.
final class ProcessGPUTime {
    struct Share {
        var percent: Double
        /// The name the client was opened under, cut to 16 characters by the kernel.
        var name: String
    }

    private struct Client {
        var pid: pid_t
        var name: String
        var nanoseconds: UInt64
    }

    /// How many readings a share is taken across. The counters move when the GPU
    /// finishes a stretch of work, so over a single interval a process that kept it
    /// busy throughout can read as idle; across three it holds its place in the list.
    private static let window = 3

    private var readings: [(time: UInt64, clients: [UInt64: Client])] = []

    /// Forgets the readings: after a sleep, or when sampling starts again.
    func reset() {
        readings.removeAll()
    }

    /// Each process's percent of the GPU's time since the oldest reading kept. Empty on
    /// the first reading, which has nothing to measure from.
    func sample() -> [pid_t: Share] {
        let now = DispatchTime.now().uptimeNanoseconds
        let clients = readClients()
        var shares: [pid_t: Share] = [:]
        for (id, client) in clients {
            // From the oldest reading that saw this client. One that none saw was opened
            // since the newest, so all of its time falls after that.
            let base: (time: UInt64, nanoseconds: UInt64)?
            if let reading = readings.first(where: { $0.clients[id] != nil }) {
                base = (reading.time, reading.clients[id]!.nanoseconds)
            } else {
                base = readings.last.map { ($0.time, 0) }
            }
            guard let base, now > base.time, client.nanoseconds >= base.nanoseconds else { continue }
            let percent = Double(client.nanoseconds - base.nanoseconds) / Double(now - base.time) * 100
            shares[client.pid, default: Share(percent: 0, name: client.name)].percent += percent
        }
        readings.append((now, clients))
        if readings.count > Self.window { readings.removeFirst() }
        for pid in shares.keys { shares[pid]!.percent = min(shares[pid]!.percent, 100) }
        return shares
    }

    /// Every accelerator's user clients, by registry entry ID. A process can hold
    /// several, and each keeps its own count.
    private func readClients() -> [UInt64: Client] {
        var clients: [UInt64: Client] = [:]
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &accelerators) == KERN_SUCCESS else { return clients }
        defer { IOObjectRelease(accelerators) }
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS
            else { continue }
            defer { IOObjectRelease(children) }
            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                guard let creator = property(child, "IOUserClientCreator") as? String,
                      let usage = property(child, "AppUsage") as? [[String: Any]],
                      let (pid, name) = Self.parseCreator(creator) else { continue }
                var nanoseconds: UInt64 = 0
                for entry in usage {
                    nanoseconds &+= (entry["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0
                }
                var id: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(child, &id) == KERN_SUCCESS else { continue }
                clients[id] = Client(pid: pid, name: name, nanoseconds: nanoseconds)
            }
        }
        return clients
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// "pid 423, WindowServer" → (423, "WindowServer").
    static func parseCreator(_ creator: String) -> (pid_t, String)? {
        guard creator.hasPrefix("pid ") else { return nil }
        let parts = creator.dropFirst(4).split(separator: ",", maxSplits: 1)
        guard let first = parts.first, let pid = pid_t(first), pid > 0 else { return nil }
        let name = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        return (pid, name)
    }
}
