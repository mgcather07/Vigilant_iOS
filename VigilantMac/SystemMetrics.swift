//
//  SystemMetrics.swift
//  Vigilant (macOS)
//
//  Samples the Mac's CPU / memory / disk / network / device info using
//  low-level Darwin APIs and produces a SystemSnapshot. CPU and network
//  are rate-based, so the collector keeps the previous sample to diff.
//

import Foundation
import Darwin

@MainActor
final class SystemMetrics {

    private var prevCPU: (user: Double, system: Double, idle: Double, nice: Double)?
    private var prevNet: (rx: UInt64, tx: UInt64)?
    private var prevNetTime: Date?

    init() {
        // Prime the deltas so the first real sample is meaningful.
        prevCPU = cpuTicks()
        let net = netCounters()
        prevNet = net
        prevNetTime = Date()
    }

    func sample() -> SystemSnapshot {
        let now = Date()
        let (user, system, idle) = cpuPercentages()
        let mem = memoryInfo()
        let swap = swapInfo()
        let disk = diskInfo()
        let currentNet = netCounters()
        let net = networkRates(current: currentNet, now: now)
        let load = loadAverages()

        return SystemSnapshot(
            capturedAt: now,
            modelName: friendlyModel(),
            osVersion: osVersionString(),
            hostName: ProcessInfo.processInfo.hostName,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            cpuUser: user,
            cpuSystem: system,
            cpuIdle: idle,
            memTotal: mem.total,
            memActive: mem.active,
            memWired: mem.wired,
            memCompressed: mem.compressed,
            memFree: mem.free,
            swapUsed: swap.used,
            swapTotal: swap.total,
            diskTotal: disk.total,
            diskFree: disk.free,
            diskVolumeName: disk.name,
            netDownBytesPerSec: net.down,
            netUpBytesPerSec: net.up,
            netTotalDown: currentNet.rx,
            netTotalUp: currentNet.tx,
            loadAvg1: load.0,
            loadAvg5: load.1,
            loadAvg15: load.2,
            cpuCoreCount: ProcessInfo.processInfo.activeProcessorCount,
            processCount: processCount()
        )
    }

    // MARK: - Load average & processes

    private func loadAverages() -> (Double, Double, Double) {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        return (loads[0], loads[1], loads[2])
    }

    private func processCount() -> Int {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return 0 }
        return size / MemoryLayout<kinfo_proc>.stride
    }

    // MARK: - CPU

    private func cpuPercentages() -> (user: Double, system: Double, idle: Double) {
        guard let current = cpuTicks() else { return (0, 0, 100) }
        defer { prevCPU = current }
        guard let prev = prevCPU else { return (0, 0, 100) }

        let dUser = current.user - prev.user
        let dSystem = current.system - prev.system
        let dIdle = current.idle - prev.idle
        let dNice = current.nice - prev.nice
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return (0, 0, 100) }

        return (
            (dUser + dNice) / total * 100,
            dSystem / total * 100,
            dIdle / total * 100
        )
    }

    private func cpuTicks() -> (user: Double, system: Double, idle: Double, nice: Double)? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (
            Double(info.cpu_ticks.0), // user
            Double(info.cpu_ticks.1), // system
            Double(info.cpu_ticks.2), // idle
            Double(info.cpu_ticks.3)  // nice
        )
    }

    // MARK: - Memory

    private func memoryInfo() -> (total: UInt64, active: UInt64, wired: UInt64, compressed: UInt64, free: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return (total, 0, 0, 0, 0)
        }
        let page = UInt64(vm_kernel_page_size)
        return (
            total,
            UInt64(stats.active_count) * page,
            UInt64(stats.wire_count) * page,
            UInt64(stats.compressor_page_count) * page,
            UInt64(stats.free_count) * page
        )
    }

    private func swapInfo() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let ok = sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0
        guard ok else { return (0, 0) }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }

    // MARK: - Disk

    private func diskInfo() -> (total: UInt64, free: UInt64, name: String) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return (0, 0, "Macintosh HD")
        }
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        let free = UInt64(values.volumeAvailableCapacity ?? 0)
        return (total, free, values.volumeName ?? "Macintosh HD")
    }

    // MARK: - Network

    private func networkRates(current: (rx: UInt64, tx: UInt64), now: Date) -> (down: Double, up: Double) {
        defer { prevNet = current; prevNetTime = now }
        guard let prev = prevNet, let prevTime = prevNetTime else { return (0, 0) }
        let dt = now.timeIntervalSince(prevTime)
        guard dt > 0 else { return (0, 0) }
        // Counters can wrap or reset; clamp negatives to 0.
        let down = current.rx >= prev.rx ? Double(current.rx - prev.rx) / dt : 0
        let up = current.tx >= prev.tx ? Double(current.tx - prev.tx) / dt : 0
        return (down, up)
    }

    private func netCounters() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let iface = ptr.pointee
            if let addr = iface.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: iface.ifa_name)
                if !name.hasPrefix("lo"), let data = iface.ifa_data {
                    let net = data.assumingMemoryBound(to: if_data.self).pointee
                    rx &+= UInt64(net.ifi_ibytes)
                    tx &+= UInt64(net.ifi_obytes)
                }
            }
            cursor = iface.ifa_next
        }
        return (rx, tx)
    }

    // MARK: - Device info

    private func osVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    private func friendlyModel() -> String {
        let raw = sysctlString("hw.model")
        return raw.isEmpty ? "Mac" : raw
    }

    private func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }
}
