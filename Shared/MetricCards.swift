//
//  MetricCards.swift
//  Shared
//
//  Reusable "widget" cards for a SystemSnapshot, shown on both the Mac
//  dashboard and the iPhone. Pure SwiftUI so both platforms share them.
//

import SwiftUI

/// Adaptive grid of monitoring cards for a snapshot.
struct MetricsGrid: View {
    let snapshot: SystemSnapshot?
    var stale: Bool = false
    /// When set, every card is forced to this exact height (uniform grid).
    var uniformHeight: CGFloat? = nil
    /// When set, the Top Memory card becomes tappable (shows a chevron) and
    /// calls this to open a full memory-usage screen.
    var onSelectMemory: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 14, alignment: .top)]

    var body: some View {
        if let snapshot {
            LazyVGrid(columns: columns, spacing: 14) {
                DeviceCard(snapshot: snapshot)
                CPUCard(snapshot: snapshot)
                LoadAverageCard(snapshot: snapshot)
                ProcessesCard(snapshot: snapshot)
                MemoryCard(snapshot: snapshot)
                if let onSelectMemory {
                    Button(action: onSelectMemory) {
                        TopMemoryCard(snapshot: snapshot, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    TopMemoryCard(snapshot: snapshot)
                }
                DiskCard(snapshot: snapshot)
                NetworkCard(snapshot: snapshot)
            }
            .environment(\.metricCardHeight, uniformHeight)
            .opacity(stale ? 0.5 : 1)
        } else {
            MetricCard(title: "System", systemImage: "waveform.path.ecg") {
                Text("Waiting for the Mac Mini to report…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Card container

struct MetricCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    @Environment(\.metricCardHeight) private var forcedHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
            if forcedHeight != nil { Spacer(minLength: 0) }
        }
        .padding(14)
        .frame(maxWidth: .infinity,
               minHeight: forcedHeight ?? 118,
               maxHeight: forcedHeight,
               alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MetricCardHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}
extension EnvironmentValues {
    var metricCardHeight: CGFloat? {
        get { self[MetricCardHeightKey.self] }
        set { self[MetricCardHeightKey.self] = newValue }
    }
}

// MARK: - Ring gauge

struct RingGauge: View {
    var fraction: Double
    var tint: Color
    var label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 64, height: 64)
    }
}

// MARK: - Cards

struct DeviceCard: View {
    let snapshot: SystemSnapshot
    var body: some View {
        MetricCard(title: "Device", systemImage: "desktopcomputer") {
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.osVersion).font(.title3.bold())
                metric("Model", snapshot.modelName)
                metric("Host", snapshot.hostName)
                metric("Up", MetricFormat.uptime(snapshot.uptimeSeconds))
            }
        }
    }
    private func metric(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(v).lineLimit(1).truncationMode(.middle)
        }
        .font(.caption)
    }
}

struct CPUCard: View {
    let snapshot: SystemSnapshot
    var body: some View {
        MetricCard(title: "Processor Load", systemImage: "cpu") {
            HStack(alignment: .center, spacing: 12) {
                RingGauge(fraction: snapshot.cpuUsed / 100,
                          tint: color(snapshot.cpuUsed),
                          label: MetricFormat.percent(snapshot.cpuUsed))
                VStack(alignment: .leading, spacing: 6) {
                    legend(.blue, "User", snapshot.cpuUser)
                    legend(.teal, "System", snapshot.cpuSystem)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func legend(_ c: Color, _ name: String, _ pct: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(name).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(MetricFormat.percent(pct)).monospacedDigit().lineLimit(1).fixedSize()
        }
        .font(.caption)
    }
    private func color(_ pct: Double) -> Color { pct > 85 ? .red : (pct > 60 ? .orange : .blue) }
}

struct MemoryCard: View {
    let snapshot: SystemSnapshot
    var body: some View {
        MetricCard(title: "Memory", systemImage: "memorychip") {
            HStack(alignment: .center, spacing: 12) {
                RingGauge(fraction: snapshot.memUsedFraction,
                          tint: color(snapshot.memUsedFraction),
                          label: MetricFormat.percent(snapshot.memUsedFraction, isFraction: true))
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(MetricFormat.bytes(snapshot.memUsed)) / \(MetricFormat.bytes(snapshot.memTotal))")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    legend(.blue, "Active", snapshot.memActive)
                    legend(.purple, "Wired", snapshot.memWired)
                    legend(.teal, "Compressed", snapshot.memCompressed)
                    if snapshot.swapUsed > 0 {
                        legend(.orange, "Swap", snapshot.swapUsed)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func legend(_ c: Color, _ name: String, _ bytes: UInt64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(name).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(MetricFormat.bytes(bytes)).monospacedDigit().lineLimit(1).fixedSize()
        }
        .font(.caption2)
    }
    private func color(_ f: Double) -> Color { f > 0.9 ? .red : (f > 0.7 ? .orange : .blue) }
}

struct DiskCard: View {
    let snapshot: SystemSnapshot
    var body: some View {
        MetricCard(title: "Disk", systemImage: "internaldrive") {
            HStack(alignment: .center, spacing: 12) {
                RingGauge(fraction: snapshot.diskUsedFraction,
                          tint: color(snapshot.diskUsedFraction),
                          label: MetricFormat.percent(snapshot.diskUsedFraction, isFraction: true))
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.diskVolumeName).font(.callout.weight(.medium)).lineLimit(1)
                    Text("\(MetricFormat.bytes(snapshot.diskUsed)) / \(MetricFormat.bytes(snapshot.diskTotal))")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func color(_ f: Double) -> Color { f > 0.9 ? .red : (f > 0.75 ? .orange : .indigo) }
}

struct NetworkCard: View {
    let snapshot: SystemSnapshot
    var body: some View {
        MetricCard(title: "Network", systemImage: "network") {
            VStack(alignment: .leading, spacing: 8) {
                row("arrow.down", .green, "Down", snapshot.netDownBytesPerSec)
                row("arrow.up", .blue, "Up", snapshot.netUpBytesPerSec)
                Divider()
                total("Total ↓", snapshot.netTotalDown)
                total("Total ↑", snapshot.netTotalUp)
            }
        }
    }
    private func row(_ symbol: String, _ c: Color, _ name: String, _ rate: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(c)
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(MetricFormat.rate(rate)).font(.callout.weight(.medium)).monospacedDigit().lineLimit(1).fixedSize()
        }
        .font(.caption)
    }
    private func total(_ name: String, _ bytes: UInt64) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(MetricFormat.bytes(bytes)).monospacedDigit().lineLimit(1).fixedSize()
        }
        .font(.caption2)
    }
}

struct LoadAverageCard: View {
    let snapshot: SystemSnapshot
    var body: some View {
        MetricCard(title: "Load Average", systemImage: "speedometer") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", snapshot.loadAvg1))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(loadColor)
                Text("1 min").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                stat("5 min", snapshot.loadAvg5)
                stat("15 min", snapshot.loadAvg15)
            }
            Text("\(snapshot.cpuCoreCount) cores")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func stat(_ name: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(String(format: "%.2f", value)).font(.callout.weight(.medium)).monospacedDigit()
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var loadColor: Color {
        guard snapshot.cpuCoreCount > 0 else { return .primary }
        let ratio = snapshot.loadAvg1 / Double(snapshot.cpuCoreCount)
        return ratio > 1 ? .red : (ratio > 0.7 ? .orange : .green)
    }
}

struct TopMemoryCard: View {
    let snapshot: SystemSnapshot
    var showsChevron: Bool = false

    private var maxBytes: UInt64 {
        snapshot.topMemoryProcesses.first?.memoryBytes ?? 1
    }

    var body: some View {
        MetricCard(title: "Top Memory", systemImage: "chart.bar.fill") {
            if snapshot.topMemoryProcesses.isEmpty {
                Text("—").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(snapshot.topMemoryProcesses.prefix(5)) { proc in
                        row(proc)
                    }
                    if showsChevron && snapshot.topMemoryProcesses.count > 5 {
                        Text("+\(snapshot.topMemoryProcesses.count - 5) more…")
                            .font(.caption2).foregroundStyle(.tint)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
        }
    }

    private func row(_ proc: ProcessMemory) -> some View {
        let fraction = maxBytes == 0 ? 0 : Double(proc.memoryBytes) / Double(maxBytes)
        return VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(proc.name).lineLimit(1).truncationMode(.middle)
                if proc.count > 1 {
                    Text("×\(proc.count)").foregroundStyle(.tertiary).fixedSize()
                }
                Spacer(minLength: 4)
                Text(MetricFormat.bytes(proc.memoryBytes))
                    .monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
            .font(.caption)
            GeometryReader { geo in
                Capsule().fill(.secondary.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.blue.gradient)
                            .frame(width: max(2, geo.size.width * fraction))
                    }
            }
            .frame(height: 4)
        }
    }
}

struct ProcessesCard: View {
    let snapshot: SystemSnapshot
    var body: some View {
        MetricCard(title: "Processes", systemImage: "square.stack.3d.up") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(snapshot.processCount)")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("running").font(.caption).foregroundStyle(.secondary)
            }
            Text("\(snapshot.cpuCoreCount) logical cores")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
