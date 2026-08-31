//
//  LogTab.swift
//  Vigilant Remote (iOS)
//
//  A history of Sentry going on and off, newest first. The Mac writes these
//  transitions to the shared record; the phone just displays them.
//

import SwiftUI

struct LogTab: View {
    @Bindable var model: RemoteModel

    private var events: [SentryEvent] {
        Array(model.store.state.events.reversed())
    }

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Sentry turning on and off will show up here.")
                    )
                } else {
                    List(events) { event in
                        row(event)
                    }
                }
            }
            .navigationTitle("Log")
            .refreshable { model.refresh() }
        }
    }

    private func row(_ event: SentryEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.on ? "bolt.fill" : "bolt.slash")
                .foregroundStyle(event.on ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(label(for: event))
                        .font(.body.weight(.medium))
                    if let trigger = event.trigger {
                        triggerBadge(trigger)
                    }
                }
                Text(event.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(event.date, format: .dateTime.hour().minute())
                    .font(.subheadline)
                Text(event.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Manual events describe the switch ("Sentry on/off"); schedule and lunch
    /// events describe the activity ("Keeping awake / Standing by").
    private func label(for event: SentryEvent) -> String {
        if event.trigger == .manual {
            return event.on ? "Sentry on" : "Sentry off"
        }
        return event.on ? "Keeping awake" : "Standing by"
    }

    private func triggerBadge(_ trigger: SentryTrigger) -> some View {
        let color: Color
        switch trigger {
        case .manual:   color = .blue
        case .schedule: color = .teal
        case .lunch:    color = .orange
        }
        return Text(trigger.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
