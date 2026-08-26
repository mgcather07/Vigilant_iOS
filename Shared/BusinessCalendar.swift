//
//  BusinessCalendar.swift
//  Shared
//
//  Swift port of the Python holiday logic. Given a set of years and a
//  policy, it builds a map of {date: holiday name} so the Mac agent can
//  skip jiggling on company holidays when the work schedule is enabled.
//

import Foundation

struct BusinessCalendar {

    /// Optional holidays the user can opt into, mirroring the Python OPTIONALS set.
    enum Optional: String, CaseIterable, Sendable, Codable, Identifiable {
        case mlk = "MLK"
        case goodFriday = "GoodFriday"
        case juneteenth = "Juneteenth"
        case christmasEve = "ChristmasEve"
        case dayAfterChristmas = "DayAfterChristmas"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .mlk:               return "Martin Luther King Jr. Day"
            case .goodFriday:        return "Good Friday"
            case .juneteenth:        return "Juneteenth"
            case .christmasEve:      return "Christmas Eve"
            case .dayAfterChristmas: return "Day After Christmas"
            }
        }
    }

    /// Holidays observed by this calendar, keyed by day.
    let holidays: [DateComponentsKey: String]

    init(years: [Int],
         includeObserved: Bool = true,
         optionals: Set<Optional> = [.goodFriday, .christmasEve, .dayAfterChristmas],
         custom: [CustomHoliday] = []) {
        var labels: [DateComponentsKey: String] = [:]
        for year in years {
            for (day, name) in Self.coreHolidays(year: year) {
                labels[day] = name
            }
            for (day, name) in Self.optionalHolidays(year: year, optionals: optionals) {
                labels[day] = name
            }
            for holiday in custom where holiday.appliesTo(year: year) {
                labels[DateComponentsKey(year: year, month: holiday.month, day: holiday.day)] = holiday.name
            }
        }
        self.holidays = includeObserved ? Self.applyObserved(labels) : labels
    }

    // MARK: - Listing

    /// All holidays as (date, name), sorted ascending.
    func sortedHolidays(calendar: Calendar = gregorian) -> [(date: Date, name: String)] {
        holidays
            .compactMap { key, name in key.date(calendar: calendar).map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
    }

    /// Upcoming holidays on or after `from`.
    func upcoming(from: Date = Date(), limit: Int = 12, calendar: Calendar = gregorian) -> [(date: Date, name: String)] {
        let startOfToday = calendar.startOfDay(for: from)
        return sortedHolidays(calendar: calendar)
            .filter { $0.date >= startOfToday }
            .prefix(limit)
            .map { $0 }
    }

    func isHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
        holidays[DateComponentsKey(date: date, calendar: calendar)] != nil
    }

    func holidayName(_ date: Date, calendar: Calendar = .current) -> String? {
        holidays[DateComponentsKey(date: date, calendar: calendar)]
    }

    // MARK: - Core holidays

    private static func coreHolidays(year: Int) -> [DateComponentsKey: String] {
        let tg = thanksgiving(year: year)
        return [
            DateComponentsKey(year: year, month: 1, day: 1):   "New Year's Day",
            DateComponentsKey(memorialDay(year: year)):        "Memorial Day",
            DateComponentsKey(year: year, month: 7, day: 4):   "Independence Day",
            DateComponentsKey(laborDay(year: year)):           "Labor Day",
            DateComponentsKey(tg):                             "Thanksgiving Day",
            DateComponentsKey(add(days: 1, to: tg)):           "Day After Thanksgiving (Black Friday)",
            DateComponentsKey(year: year, month: 12, day: 25): "Christmas Day",
        ]
    }

    private static func optionalHolidays(year: Int, optionals: Set<Optional>) -> [DateComponentsKey: String] {
        var map: [DateComponentsKey: String] = [:]
        if optionals.contains(.mlk) {
            map[DateComponentsKey(nthWeekday(year: year, month: 1, weekday: 2, n: 3))] = "Martin Luther King Jr. Day"
        }
        if optionals.contains(.goodFriday) {
            // Manual entries, matching the original script. Extend as needed.
            let goodFridays: [Int: (Int, Int)] = [
                2025: (4, 18),
                2026: (4, 3),
                2027: (3, 26),
                2028: (4, 14),
            ]
            if let (m, d) = goodFridays[year] {
                map[DateComponentsKey(year: year, month: m, day: d)] = "Good Friday"
            }
        }
        if optionals.contains(.juneteenth) {
            map[DateComponentsKey(year: year, month: 6, day: 19)] = "Juneteenth"
        }
        if optionals.contains(.christmasEve) {
            map[DateComponentsKey(year: year, month: 12, day: 24)] = "Christmas Eve"
        }
        if optionals.contains(.dayAfterChristmas) {
            map[DateComponentsKey(year: year, month: 12, day: 26)] = "Day After Christmas"
        }
        return map
    }

    /// Saturday holiday -> observed Friday; Sunday holiday -> observed Monday.
    private static func applyObserved(_ labels: [DateComponentsKey: String]) -> [DateComponentsKey: String] {
        var observed = labels
        let cal = gregorian
        for (key, name) in labels {
            guard let date = key.date(calendar: cal) else { continue }
            let weekday = cal.component(.weekday, from: date) // 1=Sun ... 7=Sat
            if weekday == 7 { // Saturday
                observed[DateComponentsKey(add(days: -1, to: date))] = "\(name) (Observed)"
            } else if weekday == 1 { // Sunday
                observed[DateComponentsKey(add(days: 1, to: date))] = "\(name) (Observed)"
            }
        }
        return observed
    }

    // MARK: - Date math helpers

    static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        gregorian.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func add(days: Int, to date: Date) -> Date {
        gregorian.date(byAdding: .day, value: days, to: date)!
    }

    /// weekday here is Calendar-style: 1=Sunday ... 7=Saturday.
    private static func nthWeekday(year: Int, month: Int, weekday: Int, n: Int) -> Date {
        let first = makeDate(year: year, month: month, day: 1)
        let firstWeekday = gregorian.component(.weekday, from: first)
        let offset = (weekday - firstWeekday + 7) % 7
        return add(days: offset + 7 * (n - 1), to: first)
    }

    private static func lastWeekday(year: Int, month: Int, weekday: Int) -> Date {
        var date: Date
        if month < 12 {
            date = add(days: -1, to: makeDate(year: year, month: month + 1, day: 1))
        } else {
            date = makeDate(year: year, month: 12, day: 31)
        }
        while gregorian.component(.weekday, from: date) != weekday {
            date = add(days: -1, to: date)
        }
        return date
    }

    // Monday=2, Thursday=5 in Calendar's 1=Sunday convention.
    private static func thanksgiving(year: Int) -> Date { nthWeekday(year: year, month: 11, weekday: 5, n: 4) }
    private static func memorialDay(year: Int) -> Date { lastWeekday(year: year, month: 5, weekday: 2) }
    private static func laborDay(year: Int) -> Date { nthWeekday(year: year, month: 9, weekday: 2, n: 1) }
}

/// A user-added holiday. `year == nil` means it recurs every year.
struct CustomHoliday: Codable, Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var month: Int
    var day: Int
    var year: Int?

    func appliesTo(year candidate: Int) -> Bool {
        year == nil || year == candidate
    }
}

/// A hashable year/month/day key so we can compare dates ignoring time.
struct DateComponentsKey: Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    init(_ date: Date, calendar: Calendar = BusinessCalendar.gregorian) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 0; self.month = c.month ?? 0; self.day = c.day ?? 0
    }

    init(date: Date, calendar: Calendar) {
        self.init(date, calendar: calendar)
    }

    func date(calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
