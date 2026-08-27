//
//  AppController.swift
//  Vigilant (macOS)
//
//  The brain of the Mac agent. Owns the CloudKit relay, the jiggle
//  engine, the schedule, and the run loop. Decides — every tick —
//  whether Vigilant should be actively jiggling, acts on it, and
//  reports a heartbeat back to the phone.
//

import Foundation

@MainActor
@Observable
final class AppController {
    static let shared = AppController()

    let store = CloudKitStore()
    @ObservationIgnored private let jiggle = JiggleEngine()
    @ObservationIgnored private let metrics = SystemMetrics()

    /// Latest live system snapshot, for the Mac's own dashboard window.
    private(set) var snapshot: SystemSnapshot?

    // Cadences (seconds)
    @ObservationIgnored private let jiggleInterval: TimeInterval = 5
    @ObservationIgnored private let heartbeatEvery = 6   // ticks -> ~30s
    @ObservationIgnored private let pollEvery = 6        // ticks -> ~30s

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tick = 0

    // Derived, observable view state for the menu bar
    private(set) var isActive = false
    private(set) var accessibilityTrusted = false
    private(set) var statusLine = "Starting…"

    @ObservationIgnored private let settings = VigilantSettings.shared
    @ObservationIgnored private var calendar: BusinessCalendar

    private init() {
        self.calendar = VigilantSettings.shared.makeCalendar(years: Self.relevantYears())
    }

    /// Called by VigilantSettings when the schedule or holiday policy changes.
    func settingsDidChange() {
        calendar = settings.makeCalendar(years: Self.relevantYears())
        evaluate()
    }

    // MARK: - Lifecycle

    func start() {
        accessibilityTrusted = jiggle.isAccessibilityTrusted
        snapshot = metrics.sample()
        Task {
            await store.start()
            evaluate()
        }
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        jiggle.endPreventSleep()
    }

    /// Called when a silent push tells us the record changed.
    func handleRemoteChange() {
        Task {
            await store.refresh()
            evaluate()
        }
    }

    func requestAccessibility() {
        jiggle.requestAccessibilityIfNeeded()
        accessibilityTrusted = jiggle.isAccessibilityTrusted
    }

    // MARK: - Menu actions (local toggle from the Mac itself)

    func toggleEnabled() {
        let target = !store.state.enabled
        Task {
            await store.setEnabled(target, source: "Mac")
            evaluate()
        }
    }

    func toggleSchedule() {
        let target = !store.state.scheduleEnabled
        Task {
            await store.setScheduleEnabled(target, source: "Mac")
            evaluate()
        }
    }

    // MARK: - Run loop

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: jiggleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func onTick() {
        tick &+= 1
        accessibilityTrusted = jiggle.isAccessibilityTrusted

        // Sample system metrics every tick for a live local dashboard.
        snapshot = metrics.sample()

        evaluate()

        if isActive {
            jiggle.jiggle()
        }

        if tick % pollEvery == 0 {
            Task { await store.refresh(); evaluate() }
        }
        if tick % heartbeatEvery == 0 {
            reportHeartbeat()
        }
    }

    // MARK: - Decision

    private func shouldBeActive(now: Date = Date()) -> Bool {
        let s = store.state
        guard s.enabled else { return false }
        guard s.scheduleEnabled else { return true } // "on" means run continuously
        // Schedule mode: only during work windows, and never on holidays.
        if calendar.isHoliday(now) { return false }
        return settings.schedule.isWithinWindow(now)
    }

    private func evaluate(now: Date = Date()) {
        let active = shouldBeActive(now: now)
        isActive = active

        if active {
            jiggle.beginPreventSleep()
        } else {
            jiggle.endPreventSleep()
        }

        statusLine = describe(now: now)
    }

    private func reportHeartbeat() {
        let status: MacStatus = isActive
            ? .running
            : (store.state.enabled ? .idleEnabled : .off)
        let snap = snapshot
        Task {
            await store.reportMac(status: status, lastActivity: jiggle.lastActivity, metrics: snap)
        }
    }

    // MARK: - Human-readable status

    private func describe(now: Date) -> String {
        let s = store.state
        if !s.enabled { return "Off duty — this Mac can sleep" }
        if !s.scheduleEnabled { return isActive ? "Keeping this Mac awake" : "On duty" }
        if calendar.isHoliday(now) {
            let name = calendar.holidayName(now) ?? "Holiday"
            return "Paused for \(name)"
        }
        if settings.schedule.isWithinWindow(now) { return "On watch — work hours" }
        return "Off watch — outside work hours"
    }

    private static func relevantYears() -> [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return [y, y + 1]
    }
}
