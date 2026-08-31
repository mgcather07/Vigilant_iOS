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

    // Transition tracking for the on/off event log.
    @ObservationIgnored private var hasInitialized = false
    @ObservationIgnored private var lastEnabled = false
    @ObservationIgnored private var lastLunchActive = false
    @ObservationIgnored private var lastLunchUntil: Date?
    // Guards the settings→CloudKit push while we're adopting a remote edit.
    @ObservationIgnored private var adoptingRemoteSchedule = false
    // Guards against repeatedly writing the lunch-cleared field while it settles.
    @ObservationIgnored private var clearingLunch = false

    private init() {
        self.calendar = VigilantSettings.shared.makeCalendar(years: Self.relevantYears())
    }

    /// Called by VigilantSettings when the schedule or holiday policy changes.
    func settingsDidChange() {
        calendar = settings.makeCalendar(years: Self.relevantYears())
        // A local edit on the Mac: mirror it up so the phone sees it. Skip the
        // push when we're only adopting a change the phone already made.
        if !adoptingRemoteSchedule {
            pushScheduleToCloud()
            publishUpcomingHolidays()
        }
        evaluate()
    }

    // MARK: - Lifecycle

    func start() {
        accessibilityTrusted = jiggle.isAccessibilityTrusted
        snapshot = metrics.sample()
        Task {
            await store.start()
            // Reconcile the shared schedule: adopt what's in the cloud (the phone
            // may have edited it while the Mac was off); if there's none yet, seed it.
            if store.state.schedule != nil {
                adoptScheduleFromCloudIfNeeded()
            } else {
                await store.setSchedule(settings.schedule, source: "Mac")
            }
            await store.setUpcomingHolidays(upcomingHolidayItems(), source: "Mac")
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
            adoptScheduleFromCloudIfNeeded()
            evaluate()
        }
    }

    func requestAccessibility() {
        jiggle.requestAccessibilityIfNeeded()
        accessibilityTrusted = jiggle.isAccessibilityTrusted
    }

    // MARK: - Menu actions (local toggle from the Mac itself)

    func setActive(_ on: Bool) {
        Task {
            await store.setActive(on, source: "Mac")
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

        // A finished lunch break: clear it so Sentry resumes and the phone's
        // countdown disappears. The Mac is the authority on the timer.
        if let until = store.state.lunchUntil, Date() >= until, !clearingLunch {
            clearingLunch = true
            Task { await store.endLunch(source: "Mac"); clearingLunch = false }
        }

        evaluate()

        if isActive {
            jiggle.jiggle()
        }

        if tick % pollEvery == 0 {
            Task { await store.refresh(); adoptScheduleFromCloudIfNeeded(); evaluate() }
        }
        if tick % heartbeatEvery == 0 {
            reportHeartbeat()
        }
    }

    // MARK: - Decision

    private func shouldBeActive(now: Date = Date()) -> Bool {
        let s = store.state
        guard s.enabled else { return false }
        if s.isOnLunch(now: now) { return false }   // paused for lunch
        guard s.scheduleEnabled else { return true } // "on" means run continuously
        // Schedule mode: only during work windows, and never on holidays.
        if calendar.isHoliday(now) { return false }
        return settings.schedule.isWithinWindow(now)
    }

    private func evaluate(now: Date = Date()) {
        let enabledNow = store.state.enabled
        let lunchActiveNow = store.state.isOnLunch(now: now)
        let active = shouldBeActive(now: now)

        // Log genuine on/off transitions (but not the very first evaluation at
        // launch, which would spuriously read as a "turned on/off" event).
        if hasInitialized && active != isActive {
            let (trigger, reason) = transitionCause(
                active: active,
                enabledChanged: enabledNow != lastEnabled,
                lunchChanged: lunchActiveNow != lastLunchActive,
                now: now)
            Task { await store.appendEvent(on: active, reason: reason, trigger: trigger, at: now, source: "Mac") }
        }
        hasInitialized = true
        lastEnabled = enabledNow
        lastLunchActive = lunchActiveNow
        lastLunchUntil = store.state.lunchUntil
        isActive = active

        if active {
            jiggle.beginPreventSleep()
        } else {
            jiggle.endPreventSleep()
        }

        statusLine = describe(now: now)
    }

    /// Classify why Sentry just flipped: a lunch break, a person toggling it
    /// (manual, with who), or the schedule (work hours / holiday).
    private func transitionCause(active: Bool, enabledChanged: Bool, lunchChanged: Bool, now: Date) -> (SentryTrigger, String) {
        if lunchChanged {
            if !active {
                return (.lunch, "Lunch — paused for 1 hour")
            }
            let expired = lastLunchUntil.map { now >= $0 } ?? true
            return (.lunch, expired ? "Lunch over — back on" : "Lunch ended early — back on")
        }
        if enabledChanged {
            let who = store.state.source   // "iPhone" or "Mac"
            let verb = active ? "Turned on" : "Turned off"
            return (.manual, "\(verb) from \(who)")
        }
        if active {
            return (.schedule, "Work hours started")
        }
        if calendar.isHoliday(now) {
            return (.schedule, "Holiday — \(calendar.holidayName(now) ?? "Holiday")")
        }
        return (.schedule, "Work hours ended")
    }

    // MARK: - Schedule sync helpers

    /// If the cloud has a different schedule than our local settings (e.g. the
    /// phone edited it), adopt it without pushing it straight back up.
    private func adoptScheduleFromCloudIfNeeded() {
        guard let remote = store.state.schedule, remote != settings.schedule else { return }
        adoptingRemoteSchedule = true
        settings.schedule = remote   // persists locally + recomputes via settingsDidChange
        adoptingRemoteSchedule = false
    }

    private func pushScheduleToCloud() {
        let schedule = settings.schedule
        Task { await store.setSchedule(schedule, source: "Mac") }
    }

    private func publishUpcomingHolidays() {
        let items = upcomingHolidayItems()
        Task { await store.setUpcomingHolidays(items, source: "Mac") }
    }

    private func upcomingHolidayItems() -> [HolidayItem] {
        calendar.upcoming(from: Date(), limit: 12).map { HolidayItem(date: $0.date, name: $0.name) }
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
        if !s.enabled { return "Sentry off — this Mac can sleep" }
        if let until = s.lunchUntil, now < until {
            return "On lunch — back at \(until.formatted(date: .omitted, time: .shortened))"
        }
        // Sentry is on (armed). "Standing by" = on but not currently keeping the
        // Mac awake — never say "off" here, that's reserved for the toggle.
        if isActive { return "Keeping this Mac awake" }
        if calendar.isHoliday(now) {
            return "Standing by — holiday (\(calendar.holidayName(now) ?? "Holiday"))"
        }
        return "Standing by — outside work hours"
    }

    private static func relevantYears() -> [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return [y, y + 1]
    }
}
