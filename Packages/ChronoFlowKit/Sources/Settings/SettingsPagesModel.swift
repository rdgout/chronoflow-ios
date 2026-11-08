import AppCore
import Foundation
import LocalStore
import Observation

@MainActor @Observable public final class SettingsPagesModel {
    public private(set) var account: AccountRecord?
    public private(set) var settings: [String: JSONObject] = [:]
    public private(set) var loaded = false
    public private(set) var settingsLoaded = false
    public private(set) var failure = false
    @ObservationIgnored private let database: AccountDatabase
    @ObservationIgnored private let permit: SessionMutationPermit
    @ObservationIgnored private let isCurrent: @Sendable () async -> Bool
    @ObservationIgnored private let delete: @MainActor (String) async throws -> Void
    @ObservationIgnored private let security: @MainActor (AccountSecurityChange) async throws -> AccountSecurityResult
    @ObservationIgnored private let requestSync: @Sendable () async -> Void
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var active = true

    public init(
        database: AccountDatabase, permit: SessionMutationPermit,
        isCurrent: @escaping @Sendable () async -> Bool,
        requestSync: @escaping @Sendable () async -> Void = {},
        delete: @escaping @MainActor (String) async throws -> Void = { _ in throw DataFailure.unsupported(.security) },
        security: @escaping @MainActor (AccountSecurityChange) async throws -> AccountSecurityResult = { _ in
            throw DataFailure.unsupported(.security)
        }
    ) {
        self.database = database
        self.permit = permit
        self.isCurrent = isCurrent
        self.requestSync = requestSync
        self.security = security
        self.delete = delete
    }

    public func start() {
        guard active, tasks.isEmpty else { return }
        tasks = [
            Task { [weak self, database] in
                do {
                    for try await value in try await AccountRepository(database: database).values() {
                        guard !Task.isCancelled, let self, self.active else { return }
                        self.account = value
                        self.loaded = true
                    }
                } catch { self?.failure = true }
            },
            Task { [weak self, database] in
                do {
                    for try await rows in try await SettingsRepository(database: database).values() {
                        guard !Task.isCancelled, let self, self.active else { return }
                        self.settingsLoaded = true
                        self.settings = Dictionary(
                            uniqueKeysWithValues: rows.compactMap { row in
                                guard let value = try? row.value.decode(JSONObject.self) else { return nil }
                                return (row.section, value)
                            })
                    }
                } catch { self?.failure = true }
            },
        ]
    }

    public func saveProfile(name: String) async throws {
        guard let account else { throw LocalMutationFailure.missingAccount }
        try await enqueue(.profile(ProfileChange(name: name, email: account.email)))
    }

    public func enqueue(_ change: OutboxChange) async throws {
        guard active, await isCurrent(), !Task.isCancelled else { throw CancellationError() }
        try await OutboxRepository(database: database).enqueue(change, permit: permit)
        await requestSync()
    }

    public func deleteAccount(password: String) async throws {
        guard active, await isCurrent(), !Task.isCancelled else { throw CancellationError() }
        try await delete(password)
    }

    public func performSecurity(_ change: AccountSecurityChange) async throws -> AccountSecurityResult {
        guard active, await isCurrent(), !Task.isCancelled else { throw CancellationError() }
        let result = try await security(change)
        guard active, await isCurrent(), !Task.isCancelled, let id = await database.accountID else {
            throw CancellationError()
        }
        if case .snapshot(let value) = result {
            try await database.write(permit: permit) { db in try StoreApplication.snapshot(value, accountID: id, db: db)
            }
        } else if case .confirmTwoFactor = change, case .codes = result {
            var value = settings["security"] ?? JSONObject()
            value["twoFactorEnabled"] = .bool(true)
            value["twoFactorConfirmedAt"] = .null
            try await SettingsRepository(database: database).upsertSecurity(value, permit: permit)
        }
        await requestSync()
        return result
    }

    public func stop() {
        active = false
        for task in tasks { task.cancel() }
        tasks.removeAll()
        account = nil
        settings = [:]
    }

    deinit { for task in tasks { task.cancel() } }
}
