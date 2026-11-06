import AppCore
import Foundation
import GRDB

public enum StoreFailure: Error, Sendable, Equatable {
    case closed, alreadyOpen, invalidAccountID, unavailable, migration, storageAttributes
}

public actor AccountDatabase {
    private let applicationSupport: URL
    public let namespace: StorageNamespace
    private var pool: DatabasePool?
    private var observations: [UUID: @Sendable () -> Void] = [:]
    public private(set) var accountID: AccountID?
    private var boundID: AccountID?
    var observationCount: Int { observations.count }
    private let migrate: @Sendable (Database) throws -> Void

    public init(applicationSupport: URL, namespace: StorageNamespace = .api) {
        self.applicationSupport = applicationSupport
        self.namespace = namespace
        migrate = SchemaV1.migrate
    }

    init(applicationSupport: URL, migration: @escaping @Sendable (Database) throws -> Void) {
        self.applicationSupport = applicationSupport
        namespace = .api
        migrate = migration
    }

    public func open(accountID value: String) throws {
        assert(!Thread.isMainThread)
        guard let id = try? AccountID(value) else { throw StoreFailure.invalidAccountID }
        guard boundID == nil || boundID == id else { throw StoreFailure.alreadyOpen }
        if pool != nil {
            guard accountID == id else { throw StoreFailure.alreadyOpen }
            return
        }
        let directory = directory(for: id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.setAttributes(directory: directory)
        } catch { throw StoreFailure.storageAttributes }
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            guard try Int.fetchOne(db, sql: "PRAGMA foreign_keys") == 1 else { throw StoreFailure.unavailable }
        }
        let opened: DatabasePool
        do {
            opened = try DatabasePool(
                path: directory.appendingPathComponent("account-\(id.rawValue).db").path,
                configuration: configuration)
        } catch { throw StoreFailure.unavailable }
        do {
            guard try opened.read({ try String.fetchOne($0, sql: "PRAGMA journal_mode") }) == "wal" else {
                throw StoreFailure.unavailable
            }
            var migrator = DatabaseMigrator()
            migrator.registerMigration("v1", migrate: migrate)
            try migrator.migrate(opened)
        } catch {
            try? opened.close()
            throw StoreFailure.migration
        }
        do { try Self.setAttributes(directory: directory) } catch {
            try? opened.close()
            throw StoreFailure.storageAttributes
        }
        pool = opened
        accountID = id
        boundID = id
    }

    public func directory(for id: AccountID) -> URL {
        applicationSupport.appendingPathComponent(namespace.directoryName, isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent(id.rawValue, isDirectory: true)
    }

    public func read<Value: Sendable>(_ fetch: @Sendable @escaping (Database) throws -> Value) async throws -> Value {
        guard let pool else { throw StoreFailure.closed }
        return try await pool.read(fetch)
    }

    public func write<Value: Sendable>(_ updates: @Sendable @escaping (Database) throws -> Value) async throws -> Value
    {
        guard let pool else { throw StoreFailure.closed }
        return try await pool.write(updates)
    }

    public func validate(epoch: SyncEpoch) throws {
        try epoch.check()
        guard accountID == epoch.accountID else { throw StoreFailure.invalidAccountID }
        guard pool != nil else { throw StoreFailure.closed }
    }

    public func write<Value: Sendable>(
        epoch: SyncEpoch, _ updates: @Sendable @escaping (Database) throws -> Value
    ) async throws -> Value {
        try epoch.check()
        guard accountID == epoch.accountID else { throw StoreFailure.invalidAccountID }
        guard let pool else { throw StoreFailure.closed }
        return try await withTaskCancellationHandler {
            try await pool.writeWithoutTransaction { db in
                try epoch.whileValid {
                    var result: Value?
                    try db.inTransaction {
                        result = try updates(db)
                        return .commit
                    }
                    return result!
                }
            }
        } onCancel: {
            epoch.invalidate()
        }
    }

    public func observe<Value: Sendable>(
        _ fetch: @Sendable @escaping (Database) throws -> Value
    ) throws -> AsyncThrowingStream<Value, any Error> {
        guard let pool else { throw StoreFailure.closed }
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<Value, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let lifetime = ObservationLifetime(continuation)
        observations[id] = { lifetime.cancel() }
        continuation.onTermination = { [weak self, weak lifetime] _ in
            lifetime?.cancel()
            Task { await self?.removeObservation(id) }
        }
        let cancellable = ValueObservation.tracking(fetch).start(
            in: pool, scheduling: .async(onQueue: DispatchQueue(label: "net.chronoflow.store.observation")),
            onError: { lifetime.fail($0) }, onChange: { lifetime.yield($0) })
        lifetime.install(cancellable)
        return stream
    }

    private func removeObservation(_ id: UUID) { observations.removeValue(forKey: id)?() }

    public func close() throws {
        for cancel in observations.values { cancel() }
        observations.removeAll()
        guard let pool else { return }
        try pool.close()
        self.pool = nil
        accountID = nil
    }

    private static func setAttributes(directory: URL) throws {
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        #if os(iOS)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in [directory] + files {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            }
        #endif
    }
}
