//
//  SentryLog.swift
//  Shared
//
//  Data that rides along in the CloudKit control record so the iPhone can
//  see and edit more than just the on/off switch:
//   - a log of Sentry going active/idle (with the reason),
//   - a read-only list of upcoming holidays the Mac will skip.
//
//  The weekly WorkSchedule itself is synced too (as JSON) — see CloudKitStore.
//

import Foundation

/// What caused a Sentry transition: a person flipping the switch, or the
/// work schedule doing it automatically.
enum SentryTrigger: String, Codable, Sendable {
    case manual
    case schedule
    case lunch

    var label: String {
        switch self {
        case .manual:   return "Manual"
        case .schedule: return "Schedule"
        case .lunch:    return "Lunch"
        }
    }
}

/// One entry in the Sentry on/off history.
struct SentryEvent: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    /// When the transition happened.
    var date: Date
    /// true = Sentry became active (keeping the Mac awake); false = went idle.
    var on: Bool
    /// Human-readable cause, e.g. "Work hours started", "Turned off from iPhone".
    var reason: String
    /// Whether a person or the schedule caused it. Optional for back-compat with
    /// events written before this field existed.
    var trigger: SentryTrigger?

    init(id: UUID = UUID(), date: Date, on: Bool, reason: String, trigger: SentryTrigger? = nil) {
        self.id = id
        self.date = date
        self.on = on
        self.reason = reason
        self.trigger = trigger
    }
}

/// A single upcoming holiday, precomputed by the Mac for read-only display on the phone.
struct HolidayItem: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(name)" }
    var date: Date
    var name: String
}

/// JSON (de)coders shared by the Mac writer and the phone reader. All of the
/// synced side-data is stored as compact JSON strings in the control record.
enum SyncCoding {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
