//
//  WorkSchedule.swift
//  Shared
//
//  The weekly work schedule, now an editable, persistable model. Decides
//  whether "now" is inside the configured work window for its weekday.
//

import Foundation

struct TimeOfDay: Codable, Sendable, Equatable, Comparable {
    var hour: Int
    var minute: Int

    var minutesSinceMidnight: Int { hour * 60 + minute }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

struct DaySchedule: Codable, Sendable, Equatable, Identifiable {
    /// Calendar weekday: 1=Sunday ... 7=Saturday.
    var weekday: Int
    var isEnabled: Bool
    var start: TimeOfDay
    var end: TimeOfDay

    var id: Int { weekday }

    /// "Monday", "Tuesday", … from the current locale.
    var name: String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(weekday - 1) % 7]
    }
}

struct WorkSchedule: Codable, Sendable, Equatable {
    /// Exactly 7 entries, ordered Monday→Sunday for display.
    var days: [DaySchedule]

    /// Mirrors the original Python schedule (Mon–Fri on, weekends off).
    static let `default` = WorkSchedule(days: [
        DaySchedule(weekday: 2, isEnabled: true,  start: .init(hour: 7, minute: 55), end: .init(hour: 17, minute: 0)),
        DaySchedule(weekday: 3, isEnabled: true,  start: .init(hour: 7, minute: 55), end: .init(hour: 17, minute: 15)),
        DaySchedule(weekday: 4, isEnabled: true,  start: .init(hour: 7, minute: 55), end: .init(hour: 17, minute: 5)),
        DaySchedule(weekday: 5, isEnabled: true,  start: .init(hour: 7, minute: 55), end: .init(hour: 17, minute: 10)),
        DaySchedule(weekday: 6, isEnabled: true,  start: .init(hour: 7, minute: 55), end: .init(hour: 17, minute: 0)),
        DaySchedule(weekday: 7, isEnabled: false, start: .init(hour: 9, minute: 0),  end: .init(hour: 17, minute: 0)),
        DaySchedule(weekday: 1, isEnabled: false, start: .init(hour: 9, minute: 0),  end: .init(hour: 17, minute: 0)),
    ])

    func day(forWeekday weekday: Int) -> DaySchedule? {
        days.first { $0.weekday == weekday }
    }

    func todaysWindow(_ now: Date = Date(), calendar: Calendar = .current) -> DaySchedule? {
        let weekday = calendar.component(.weekday, from: now)
        guard let day = day(forWeekday: weekday), day.isEnabled else { return nil }
        return day
    }

    /// Is `now` inside an enabled work window for its weekday?
    func isWithinWindow(_ now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let day = todaysWindow(now, calendar: calendar) else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return minutes >= day.start.minutesSinceMidnight && minutes <= day.end.minutesSinceMidnight
    }
}
