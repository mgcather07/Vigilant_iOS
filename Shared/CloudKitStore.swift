//
//  CloudKitStore.swift
//  Shared
//
//  The relay. Both the Mac agent and the iPhone app talk to a single
//  record ("controlState") in the user's *private* CloudKit database.
//  Outbound-only connections to iCloud are what let the phone reach the
//  Mac Mini from anywhere without a VPN or port forwarding.
//
//  - iPhone writes `enabled` / `scheduleEnabled`.
//  - Mac reads those and writes back heartbeat + status.
//  - A silent-push subscription wakes each side on change; a polling
//    timer (owned by each app) is the fallback.
//

import Foundation
import CloudKit
import os

enum VigilantCloud {
    /// Must match the iCloud container in BOTH targets' entitlements.
    static let containerIdentifier = "iCloud.io.vigilant.co.Vigilant"
    static let recordType = "VigilantControl"
    static let recordName = "controlState"
    static let subscriptionID = "vigilant-control-changes"
}

@MainActor
@Observable
final class CloudKitStore {

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case ok(Date)
        case unavailable(String)
        case error(String)
    }

    enum AccountAvailability: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case error(String)
    }

    // Observable UI state
    private(set) var state: VigilantState = .default
    private(set) var sync: SyncStatus = .idle
    private(set) var account: AccountAvailability = .unknown

    /// Local/offline mode: run without CloudKit at all. Used when iCloud isn't
    /// wired up yet (e.g. an unsigned local build) so the app is still usable
    /// standalone. Enabled by launching with `VIGILANT_LOCAL=1`.
    let isLocalOnly: Bool
    private let container: CKContainer?
    private var database: CKDatabase? { container?.privateCloudDatabase }
    private let recordID = CKRecord.ID(recordName: VigilantCloud.recordName)
    private var cachedRecord: CKRecord?

    private let log = Logger(subsystem: "io.vigilant.co", category: "CloudKitStore")

    init(containerIdentifier: String = VigilantCloud.containerIdentifier) {
        let local = ProcessInfo.processInfo.environment["VIGILANT_LOCAL"] == "1"
        self.isLocalOnly = local
        self.container = local ? nil : CKContainer(identifier: containerIdentifier)
        if local {
            self.account = .available
            self.state = VigilantState(enabled: false, scheduleEnabled: false,
                                       source: "Local", updatedAt: Date(),
                                       macStatus: .off, macLastSeen: nil, macLastActivity: nil,
                                       metrics: nil)
        }
    }

    // MARK: - Lifecycle

    /// Check the account, load the record, and register the push subscription.
    func start() async {
        guard !isLocalOnly else { sync = .ok(Date()); return }
        await refreshAccountStatus()
        guard account == .available else { return }
        await refresh()
        await ensureSubscription()
    }

    func refreshAccountStatus() async {
        guard let container else { account = .available; return }
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:            account = .available
            case .noAccount:            account = .noAccount
            case .restricted:           account = .restricted
            case .couldNotDetermine:    account = .error("Could not determine iCloud status")
            case .temporarilyUnavailable: account = .error("iCloud temporarily unavailable")
            @unknown default:           account = .error("Unknown iCloud status")
            }
        } catch {
            account = .error(error.localizedDescription)
        }
    }

    // MARK: - Reading

    /// Fetch the latest record and publish it as `state`.
    func refresh() async {
        guard !isLocalOnly else { sync = .ok(Date()); return }
        sync = .syncing
        do {
            let record = try await fetchOrCreateRecord()
            cachedRecord = record
            state = Self.state(from: record)
            sync = .ok(Date())
        } catch let ckError as CKError where ckError.code == .notAuthenticated {
            sync = .unavailable("Sign in to iCloud to use Vigilant.")
        } catch {
            log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            sync = .error(error.localizedDescription)
        }
    }

    // MARK: - Writing (iPhone side mostly)

    func setEnabled(_ enabled: Bool, source: String) async {
        await modify(source: source) { record in
            record["enabled"] = (enabled ? 1 : 0) as Int64
        }
    }

    func setScheduleEnabled(_ scheduleEnabled: Bool, source: String) async {
        await modify(source: source) { record in
            record["scheduleEnabled"] = (scheduleEnabled ? 1 : 0) as Int64
        }
    }

    // MARK: - Writing (Mac heartbeat)

    func reportMac(status: MacStatus, lastActivity: Date?, metrics: SystemSnapshot? = nil, now: Date = Date()) async {
        await modify(source: "Mac", touchUpdatedAt: false) { record in
            record["macStatus"] = status.rawValue as String
            record["macLastSeen"] = now as Date
            if let lastActivity { record["macLastActivity"] = lastActivity as Date }
            if let json = metrics?.jsonString() { record["metrics"] = json as String }
        }
    }

    // MARK: - Mutation core (with conflict retry)

    private func modify(source: String,
                        touchUpdatedAt: Bool = true,
                        _ mutate: @escaping (CKRecord) -> Void) async {
        if isLocalOnly {
            // Apply the same mutation to a standalone record and publish it.
            let record = cachedRecord ?? CKRecord(recordType: VigilantCloud.recordType, recordID: recordID)
            mutate(record)
            record["source"] = source as String
            if touchUpdatedAt { record["updatedAt"] = Date() as Date }
            cachedRecord = record
            state = Self.state(from: record)
            sync = .ok(Date())
            return
        }
        sync = .syncing
        do {
            try await saveWithRetry(source: source, touchUpdatedAt: touchUpdatedAt, mutate: mutate, retriesLeft: 2)
            sync = .ok(Date())
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
            sync = .error(error.localizedDescription)
        }
    }

    private func saveWithRetry(source: String,
                               touchUpdatedAt: Bool,
                               mutate: @escaping (CKRecord) -> Void,
                               retriesLeft: Int) async throws {
        guard let database else { return }
        let record = try await fetchOrCreateRecord()
        mutate(record)
        record["source"] = source as String
        if touchUpdatedAt { record["updatedAt"] = Date() as Date }

        do {
            let saved = try await database.save(record)
            cachedRecord = saved
            state = Self.state(from: saved)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Someone else changed the record; drop our cache and retry on top of theirs.
            cachedRecord = error.serverRecord
            guard retriesLeft > 0 else { throw error }
            try await saveWithRetry(source: source,
                                    touchUpdatedAt: touchUpdatedAt,
                                    mutate: mutate,
                                    retriesLeft: retriesLeft - 1)
        }
    }

    private func fetchOrCreateRecord() async throws -> CKRecord {
        guard let database else {
            return cachedRecord ?? CKRecord(recordType: VigilantCloud.recordType, recordID: recordID)
        }
        do {
            let record = try await database.record(for: recordID)
            cachedRecord = record
            return record
        } catch let error as CKError where error.code == .unknownItem {
            // First run: create the singleton record.
            let record = CKRecord(recordType: VigilantCloud.recordType, recordID: recordID)
            record["enabled"] = 0 as Int64
            record["scheduleEnabled"] = 0 as Int64
            record["source"] = "system" as String
            record["updatedAt"] = Date() as Date
            cachedRecord = record
            return record
        }
    }

    // MARK: - Subscription (silent push)

    func ensureSubscription() async {
        guard let database else { return }
        let subscription = CKQuerySubscription(
            recordType: VigilantCloud.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: VigilantCloud.subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent push, no alert
        subscription.notificationInfo = info

        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription with this ID already exists — fine.
            log.debug("subscription already present")
        } catch {
            log.error("subscription failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Mapping

    private static func state(from record: CKRecord) -> VigilantState {
        let statusRaw = record["macStatus"] as? String ?? MacStatus.unknown.rawValue
        return VigilantState(
            enabled: (record["enabled"] as? Int64 ?? 0) == 1,
            scheduleEnabled: (record["scheduleEnabled"] as? Int64 ?? 0) == 1,
            source: record["source"] as? String ?? "system",
            updatedAt: record["updatedAt"] as? Date ?? .distantPast,
            macStatus: MacStatus(rawValue: statusRaw) ?? .unknown,
            macLastSeen: record["macLastSeen"] as? Date,
            macLastActivity: record["macLastActivity"] as? Date,
            metrics: SystemSnapshot.from(jsonString: record["metrics"] as? String)
        )
    }
}
