//
//  ContentView.swift
//  Vigilant Remote (iOS)
//
//  One big switch, plus a live view of what the Mac Mini is doing.
//

import SwiftUI

struct ContentView: View {
    @Bindable var model: RemoteModel

    private var state: VigilantState { model.store.state }
    private var macOnline: Bool { state.isMacOnline() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    powerCard
                    statusCard
                    monitoringSection
                    scheduleCard
                    iCloudNotice
                }
                .padding()
            }
            .navigationTitle("Vigilant")
            .refreshable { model.refresh() }
        }
    }

    // MARK: - Power

    private var powerCard: some View {
        VStack(spacing: 16) {
            Image(systemName: state.enabled ? "eye.fill" : "eye.slash")
                .font(.system(size: 56))
                .foregroundStyle(state.enabled ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))

            Text(state.enabled ? "Sentry on duty" : "Sentry off duty")
                .font(.title2.bold())

            Toggle("Sentry", isOn: Binding(
                get: { state.enabled },
                set: { model.setEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(1.4)
            .padding(.vertical, 4)
            .disabled(model.isBusy)

            if model.isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(macOnline ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(macOnline ? "Mac Mini online" : "Mac Mini not responding")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

            row("Status", state.macStatus.displayName)
            row("Last heartbeat", relative(state.macLastSeen))
            row("Last activity", relative(state.macLastActivity))
            row("Last changed by", state.source)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Monitoring

    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mac Mini").font(.headline)
                Spacer()
                if let m = state.metrics {
                    Text(relative(m.capturedAt))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            MetricsGrid(snapshot: state.metrics, stale: !macOnline)
        }
    }

    // MARK: - Schedule

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { state.scheduleEnabled },
                set: { model.setScheduleEnabled($0) }
            )) {
                Text("Follow work schedule")
                    .font(.subheadline.weight(.medium))
            }
            Text("When on, the Mac only stays active during your Mon–Fri work hours and skips holidays. When off, it runs whenever Sentry is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var iCloudNotice: some View {
        if case .available = model.store.account {
            EmptyView()
        } else {
            Label(accountMessage, systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var accountMessage: String {
        switch model.store.account {
        case .noAccount: return "Sign in to iCloud in Settings to control Vigilant."
        case .restricted: return "iCloud is restricted on this device."
        case .unknown: return "Checking iCloud…"
        case .error(let m): return m
        case .available: return ""
        }
    }

    // MARK: - Helpers

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    ContentView(model: .shared)
}
