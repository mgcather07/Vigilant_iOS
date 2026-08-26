//
//  SystemSnapshot.swift
//  Shared
//
//  A point-in-time snapshot of the Mac Mini's health. Collected on the
//  Mac (see SystemMetrics.swift), shown in the Mac window, and synced
//  through CloudKit so the iPhone can monitor the server remotely.
//

import Foundation

struct SystemSnapshot: Codable, Sendable, Equatable {
    var capturedAt: Date

    // Device
    var modelName: String
    var osVersion: String
    var hostName: String
    var uptimeSeconds: Double

    // CPU (percentages 0–100, averaged over the sample interval)
    var cpuUser: Double
    var cpuSystem: Double
    var cpuIdle: Double

    // Memory (bytes)
    var memTotal: UInt64
    var memActive: UInt64
    var memWired: UInt64
    var memCompressed: UInt64
    var memFree: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64

    // Disk (bytes) for the boot volume
    var diskTotal: UInt64
    var diskFree: UInt64
    var diskVolumeName: String

    // Network throughput (bytes/sec) since the previous sample
    var netDownBytesPerSec: Double
    var netUpBytesPerSec: Double
    // Cumulative network totals since boot (bytes)
    var netTotalDown: UInt64
    var netTotalUp: UInt64

    // Load & processes
    var loadAvg1: Double
    var loadAvg5: Double
    var loadAvg15: Double
    var cpuCoreCount: Int
    var processCount: Int

    // MARK: - Derived values

    var cpuUsed: Double { min(100, max(0, cpuUser + cpuSystem)) }

    var memUsed: UInt64 { memActive &+ memWired &+ memCompressed }
    var memUsedFraction: Double {
        memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal)
    }

    var diskUsed: UInt64 { diskTotal > diskFree ? diskTotal - diskFree : 0 }
    var diskUsedFraction: Double {
        diskTotal == 0 ? 0 : Double(diskUsed) / Double(diskTotal)
    }

    // MARK: - JSON (for the CloudKit `metrics` field)

    func jsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func from(jsonString: String?) -> SystemSnapshot? {
        guard let jsonString, let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SystemSnapshot.self, from: data)
    }
}

// MARK: - Formatting helpers

enum MetricFormat {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func rate(_ bytesPerSec: Double) -> String {
        let v = Int64(max(0, bytesPerSec))
        return ByteCountFormatter.string(fromByteCount: v, countStyle: .memory) + "/s"
    }

    static func percent(_ fractionOrValue: Double, isFraction: Bool = false) -> String {
        let pct = isFraction ? fractionOrValue * 100 : fractionOrValue
        return String(format: "%.1f%%", pct)
    }

    static func uptime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let mins = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}
