//
//  OverviewView.swift
//  Vigilant (macOS)
//
//  The landing screen: the big power control, schedule summary, and a
//  quick glance at the Mac's health.
//

import SwiftUI

struct OverviewView: View {
    @Bindable var controller: AppController

    private var state: VigilantState { controller.store.state }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero

                if !controller.accessibilityTrusted {
                    AccessibilityBanner { controller.requestAccessibility() }
                }

                scheduleRow

                VStack(alignment: .leading, spacing: 10) {
                    Text("Mac Mini").font(.title3.bold())
                    quickGlance
                }
            }
            .padding(24)
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { controller.handleRemoteChange() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(controller.isActive ? Color.green.gradient : Color.gray.gradient)
                    .frame(width: 84, height: 84)
                    .shadow(color: (controller.isActive ? Color.green : .gray).opacity(0.35), radius: 12, y: 4)
                Image(systemName: state.enabled ? "eye.fill" : "eye.slash")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(state.enabled ? "Sentry on duty" : "Sentry off duty")
                    .font(.largeTitle.bold())
                Text(controller.statusLine)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { state.enabled },
                set: { _ in controller.toggleEnabled() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(1.3)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Schedule summary

    private var scheduleRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("Follow work schedule").font(.headline)
                Text(scheduleSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { state.scheduleEnabled },
                set: { _ in controller.toggleSchedule() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var scheduleSummary: String {
        if !state.scheduleEnabled {
            return "Off — Sentry stays on watch continuously while on duty."
        }
        if let day = VigilantSettings.shared.schedule.todaysWindow() {
            return "Today: \(timeString(day.start))–\(timeString(day.end)), holidays skipped."
        }
        return "No work window today."
    }

    private func timeString(_ t: TimeOfDay) -> String {
        String(format: "%d:%02d", t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour), t.minute)
            + (t.hour >= 12 ? " PM" : " AM")
    }

    // MARK: - Quick glance

    @ViewBuilder
    private var quickGlance: some View {
        if let snapshot = controller.snapshot {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 14, alignment: .top)], spacing: 14) {
                CPUCard(snapshot: snapshot)
                MemoryCard(snapshot: snapshot)
                DiskCard(snapshot: snapshot)
            }
        } else {
            Text("Collecting metrics…")
                .foregroundStyle(.secondary)
        }
    }
}

/// Shared banner prompting the user to grant Accessibility.
struct AccessibilityBanner: View {
    var onGrant: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility permission needed").font(.headline)
                Text("Vigilant needs Accessibility access to move the cursor. Without it, jiggling won't reset idle timers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Grant…", action: onGrant)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
