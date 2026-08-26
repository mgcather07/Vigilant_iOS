//
//  MonitorView.swift
//  Vigilant (macOS)
//
//  Full system-monitoring view for the Mac Mini.
//

import SwiftUI

struct MonitorView: View {
    @Bindable var controller: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let snapshot = controller.snapshot {
                    MetricsGrid(snapshot: snapshot, uniformHeight: 178)
                    lastUpdated(snapshot.capturedAt)
                } else {
                    ProgressView("Collecting metrics…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(24)
        }
        .navigationTitle("Monitor")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { controller.handleRemoteChange() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    private func lastUpdated(_ date: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
            Text("Updated \(date.formatted(date: .omitted, time: .standard)) · refreshes every 5s")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }
}
