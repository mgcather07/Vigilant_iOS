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

    func setEnabled(_ on: Bool) {
        isBusy = true
        Task {
            await store.setEnabled(on, source: "iPhone")
            isBusy = false
        }
    }

    func setScheduleEnabled(_ on: Bool) {
        Task { await store.setScheduleEnabled(on, source: "iPhone") }
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
