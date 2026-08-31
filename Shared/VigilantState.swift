//
//  VigilantState.swift
//  Shared between Vigilant (macOS) and Vigilant Remote (iOS)
//
//  A Sendable snapshot of the single control record that both devices
//  read and write through CloudKit. The macOS agent acts on `enabled`
//  (optionally gated by the work schedule) and reports its own status
//  back so the phone can show a live view.
//

import Foundation

/// What the Mac agent is currently doing.
enum MacStatus: String, Sendable, Codable {
    case running          // actively jiggling right now
    case idleEnabled      // switched on, but waiting (outside schedule / holiday)
    case off              // switched off
    case unknown          // no heartbeat yet

    var displayName: String {
        switch self {
        case .running:     return "Standing guard"
        case .idleEnabled: return "On duty — waiting"
        case .off:         return "Off duty"
        case .unknown:     return "Unknown"
        }
    }
}

/// Immutable, Sendable snapshot of the shared control record.
struct VigilantState: Sendable, Equatable {
    /// Master on/off switch (the thing the phone toggles).
    var enabled: Bool
    /// When true, the Mac only runs during work hours and skips holidays.
    /// When false, "enabled" means run continuously.
    var scheduleEnabled: Bool
    /// Who last changed the record ("iPhone" / "Mac").
    var source: String
    /// When the record was last modified.
    var updatedAt: Date

    // ---- Written by the Mac agent (heartbeat / telemetry) ----
    var macStatus: MacStatus
    var macLastSeen: Date?
    var macLastActivity: Date?

    /// Latest system-monitoring snapshot reported by the Mac (nil until first heartbeat).
    var metrics: SystemSnapshot?

    // ---- Synced side-data so the phone can do more than toggle ----
    /// The weekly work schedule, synced so the phone can view/edit it. nil until first sync.
    var schedule: WorkSchedule? = nil
    /// Recent Sentry on/off transitions (most recent last), capped by the writer.
    var events: [SentryEvent] = []
    /// Upcoming holidays the Mac will skip, precomputed for read-only display.
    var upcomingHolidays: [HolidayItem] = []
    /// When set to a future time, Sentry is on a temporary lunch break until then;
    /// the Mac resumes it automatically. nil when not on a break.
    var lunchUntil: Date? = nil

    /// Whether a lunch break is currently in effect.
    func isOnLunch(now: Date = Date()) -> Bool {
        guard let until = lunchUntil else { return false }
        return now < until
    }

    static let `default` = VigilantState(
        enabled: false,
        scheduleEnabled: false,
        source: "system",
        updatedAt: .distantPast,
        macStatus: .unknown,
        macLastSeen: nil,
        macLastActivity: nil,
        metrics: nil
    )

    /// The Mac is considered online if it has checked in recently.
    func isMacOnline(now: Date = Date(), staleAfter: TimeInterval = 90) -> Bool {
        guard let seen = macLastSeen else { return false }
        return now.timeIntervalSince(seen) < staleAfter
    }
}
