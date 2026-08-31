//
//  MemoryUsageView.swift
//  Vigilant Remote (iOS)
//
//  The full "what's using memory" screen: every process the Mac reported,
//  largest first, plus the overall memory summary. Opened from the Top
//  Memory card on the Home tab.
//

import SwiftUI

struct MemoryUsageView: View {
    let snapshot: SystemSnapshot?

    var body: some View {
        Group {
            if let snapshot, !snapshot.topMemoryProcesses.isEmpty {
                List {
                    Section("Overview") {
                        summaryRow("In use",
                                   "\(MetricFormat.bytes(snapshot.memUsed)) / \(MetricFormat.bytes(snapshot.memTotal))")
                        summaryRow("Used", MetricFormat.percent(snapshot.memUsedFraction, isFraction: true))
                        summaryRow("Active", MetricFormat.bytes(snapshot.memActive))
                        summaryRow("Wired", MetricFormat.bytes(snapshot.memWired))
                        summaryRow("Compressed", MetricFormat.bytes(snapshot.memCompressed))
                        if snapshot.swapUsed > 0 {
                            summaryRow("Swap", MetricFormat.bytes(snapshot.swapUsed))
                        }
                    }

                    Section("Processes by memory") {
                        ForEach(snapshot.topMemoryProcesses) { proc in
                            processRow(proc, max: snapshot.topMemoryProcesses.first?.memoryBytes ?? 1)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No data yet",
                    systemImage: "memorychip",
                    description: Text("Waiting for the Mac Mini to report.")
                )
            }
        }
        .navigationTitle("Memory Usage")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func processRow(_ proc: ProcessMemory, max: UInt64) -> some View {
        let fraction = max == 0 ? 0 : Double(proc.memoryBytes) / Double(max)
        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text(proc.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                Text(MetricFormat.bytes(proc.memoryBytes))
                    .monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
            .font(.subheadline)

            GeometryReader { geo in
                Capsule().fill(.secondary.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.blue.gradient)
                            .frame(width: Swift.max(2, geo.size.width * fraction))
                    }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 2)
    }
}
