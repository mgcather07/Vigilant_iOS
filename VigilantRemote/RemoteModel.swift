//
//  RemoteModel.swift
//  Vigilant Remote (iOS)
//
//  Thin view model over the shared CloudKitStore: exposes toggles, a
//  live status view, and a polling fallback for when a push is missed.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class RemoteModel {
    static let shared = RemoteModel()

    let store = CloudKitStore()
    private var pollTimer: Timer?
    private(set) var isBusy = false

    private init() {}

    func start() {
        Task {
            await store.start()
        }
        startPolling()
    }

    func refresh() {
        Task { await store.refresh() }
    }

    /// Called from the app delegate when a silent push arrives.
    func handleRemoteChange() {
        Task { await store.refresh() }
    }

    // MARK: - Actions

    func setActive(_ on: Bool) {
        isBusy = true
        Task {
            await store.setActive(on, source: "iPhone")
            isBusy = false
        }
    }

    /// Push edited work-schedule windows up to CloudKit (the Mac adopts them).
    func setSchedule(_ schedule: WorkSchedule) {
        isBusy = true
        Task {
            await store.setSchedule(schedule, source: "iPhone")
            isBusy = false
        }
    }

    // MARK: - Lunch break

    /// Pause Sentry for `minutes` (default 60); the Mac resumes it automatically.
    func startLunch(minutes: Int = 60) {
        let until = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        isBusy = true
        Task {
            await store.startLunch(until: until, source: "iPhone")
            isBusy = false
        }
    }

    /// End a lunch break early and resume Sentry now.
    func cancelLunch() {
        isBusy = true
        Task {
            await store.endLunch(source: "iPhone")
            isBusy = false
        }
    }

    // MARK: - Polling fallback (every 20s while foregrounded)

    func startPolling() {
        pollTimer?.invalidate()
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
