//
//  MenuBarView.swift
//  Vigilant (macOS)
//
//  The little panel that drops down from the menu bar icon.
//

import SwiftUI

struct MenuBarView: View {
    @Bindable var controller: AppController

    private var state: VigilantState { controller.store.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            Toggle("Sentry", isOn: Binding(
                get: { state.enabled },
                set: { controller.setActive($0) }
            ))
            .toggleStyle(.switch)
            .help("When on, Sentry runs on your work schedule — active during Mon–Fri work hours, skipping holidays.")

            if !controller.accessibilityTrusted {
                accessibilityWarning
            }

            Divider()

            statusFooter

            HStack {
                Button("Refresh") { controller.handleRemoteChange() }
                Spacer()
                Button("Quit Vigilant") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.isActive ? "eye.fill" : "eye")
                .foregroundStyle(controller.isActive ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vigilant").font(.headline)
                Text(controller.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility permission needed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Text("Vigilant needs Accessibility access to move the cursor. Without it, jiggling won't reset idle timers.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Grant access…") { controller.requestAccessibility() }
                .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Last changed by", value: state.source)
            if let seen = state.macLastSeen {
                LabeledContent("Last heartbeat", value: seen.formatted(date: .omitted, time: .standard))
            }
            LabeledContent("iCloud", value: accountText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var accountText: String {
        switch controller.store.account {
        case .available: return "Connected"
        case .noAccount: return "Not signed in"
        case .restricted: return "Restricted"
        case .unknown: return "Checking…"
        case .error(let m): return m
        }
    }
}
