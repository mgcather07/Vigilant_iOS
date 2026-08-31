//
//  ContentView.swift
//  Vigilant Remote (iOS)
//
//  Tabbed remote: Home (the switch + live Mac status), Schedule (view/edit
//  the work windows), and Log (a history of Sentry going on and off).
//

import SwiftUI

struct ContentView: View {
    @Bindable var model: RemoteModel

    var body: some View {
        TabView {
            HomeTab(model: model)
                .tabItem { Label("Home", systemImage: "eye") }

            ScheduleTab(model: model)
                .tabItem { Label("Schedule", systemImage: "calendar") }

            LogTab(model: model)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
        }
    }
}

// MARK: - Home

struct HomeTab: View {
    @Bindable var model: RemoteModel
    @State private var showMemory = false

    private var state: VigilantState { model.store.state }
    private var macOnline: Bool { state.isMacOnline() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    powerCard
                    lunchCard
                    statusCard
                    monitoringSection
                    iCloudNotice
                }
                .padding()
            }
            .navigationTitle("Vigilant")
            .refreshable { model.refresh() }
            .navigationDestination(isPresented: $showMemory) {
                MemoryUsageView(snapshot: state.metrics)
            }
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
                set: { model.setActive($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(1.4)
            .padding(.vertical, 4)
            .disabled(model.isBusy)

            Text("Runs on your work schedule — active during work hours, skipping holidays.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if model.isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Lunch

    @ViewBuilder
    private var lunchCard: some View {
        // A per-second tick so the countdown updates and the card flips itself
        // when the break ends, even before the Mac clears the flag in CloudKit.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            if let until = state.lunchUntil, until > now {
                onLunchView(until: until, now: now)
            } else if state.lunchUntil != nil {
                // Expired locally; waiting for the Mac to resume Sentry.
                Label("Resuming Sentry…", systemImage: "hourglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            } else if state.enabled {
                startLunchButton
            }
        }
    }

    private func onLunchView(until: Date, now: Date) -> some View {
        VStack(spacing: 12) {
            Label("On lunch", systemImage: "fork.knife")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(countdown(to: until, from: now))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("Sentry resumes at \(until.formatted(date: .omitted, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(role: .cancel) { model.cancelLunch() } label: {
                Label("Resume now", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
    }

    private var startLunchButton: some View {
        Button { model.startLunch() } label: {
            HStack(spacing: 12) {
                Image(systemName: "fork.knife").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Take a lunch break").font(.headline)
                    Text("Pause Sentry for 1 hour, then auto-resume")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy)
    }

    private func countdown(to until: Date, from now: Date) -> String {
        let secs = max(0, Int(until.timeIntervalSince(now).rounded()))
        return String(format: "%d:%02d", secs / 60, secs % 60)
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
            MetricsGrid(snapshot: state.metrics, stale: !macOnline,
                        onSelectMemory: { showMemory = true })
        }
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
