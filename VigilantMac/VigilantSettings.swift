//
//  VigilantSettings.swift
//  Vigilant (macOS)
//
//  User-editable configuration for the schedule and holiday policy,
//  persisted to UserDefaults. Edits here drive AppController's decision
//  of when to keep the Mac active.
//

import Foundation

@MainActor
@Observable
final class VigilantSettings {
    static let shared = VigilantSettings()

    var schedule: WorkSchedule { didSet { save() } }
    var optionalHolidays: Set<BusinessCalendar.Optional> { didSet { save() } }
    var includeObserved: Bool { didSet { save() } }
    var customHolidays: [CustomHoliday] { didSet { save() } }

    private let defaultsKey = "VigilantSettings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: "VigilantSettings.v1"),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            schedule = stored.schedule
            optionalHolidays = Set(stored.optionalHolidays)
            includeObserved = stored.includeObserved
            customHolidays = stored.customHolidays
        } else {
            schedule = .default
            optionalHolidays = [.goodFriday, .christmasEve, .dayAfterChristmas]
            includeObserved = true
            customHolidays = []
        }
    }

    /// A calendar built from the current holiday policy, for the given years.
    func makeCalendar(years: [Int]) -> BusinessCalendar {
        BusinessCalendar(years: years,
                         includeObserved: includeObserved,
                         optionals: optionalHolidays,
                         custom: customHolidays)
    }

    func resetScheduleToDefault() {
        schedule = .default
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        var schedule: WorkSchedule
        var optionalHolidays: [BusinessCalendar.Optional]
        var includeObserved: Bool
        var customHolidays: [CustomHoliday]
    }

    private func save() {
        let stored = Stored(schedule: schedule,
                            optionalHolidays: Array(optionalHolidays),
                            includeObserved: includeObserved,
                            customHolidays: customHolidays)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        // Let the running agent pick up the change immediately.
        AppController.shared.settingsDidChange()
    }
}
