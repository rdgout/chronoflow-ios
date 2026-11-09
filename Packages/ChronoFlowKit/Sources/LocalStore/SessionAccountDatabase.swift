import AppCore
import Foundation
import GRDB

public actor SessionAccountDatabase: SessionAccountStore {
    private let applicationSupport: URL
    private let namespace: StorageNamespace
    private var database: AccountDatabase?
    private var isClosing = false
    private let detach: @Sendable () async -> Void

    public init(applicationSupport: URL, namespace: StorageNamespace, detach: @escaping @Sendable () async -> Void = {})
    {
        self.applicationSupport = applicationSupport
        self.namespace = namespace
        self.detach = detach
    }

    public func activeDatabase() -> AccountDatabase? { isClosing ? nil : database }

    public func open(accountID: AccountID) async throws {
        if let database, await database.accountID == accountID { return }
        try await close()
        let candidate = AccountDatabase(applicationSupport: applicationSupport, namespace: namespace)
        try await candidate.open(accountID: accountID.rawValue)
        database = candidate
    }

    public func upsert(_ account: SessionAccount) async throws {
        guard let database, let id = await database.accountID, id == (try AccountID(account.id)) else {
            throw StoreFailure.invalidAccountID
        }
        try await database.write { db in
            var record =
                try AccountRecord.fetchOne(db, key: id.rawValue)
                ?? AccountRecord(id: id.rawValue, name: account.name, email: account.email)
            record.name = account.name
            record.email = account.email
            record.hasVerifiedEmail = account.hasVerifiedEmail
            record.walkthroughSeen =
                try account.walkthroughSeen
                || StoreApplication.pending(db).contains { $0.kind == "walkthrough" }
            try record.save(db)
            let data = try JSONEncoder().encode(account.policies)
            try SettingsRecord(section: "policies", value: JSONDocument(String(decoding: data, as: UTF8.self))).save(db)
        }
    }

    public func markEmailVerified(accountID: AccountID, email: String) async throws -> Bool {
        guard let database, await database.accountID == accountID else { return false }
        return try await database.write { db in
            guard var record = try AccountRecord.fetchOne(db, key: accountID.rawValue), record.email == email else {
                return false
            }
            record.hasVerifiedEmail = true
            try record.save(db)
            return true
        }
    }

    public func close() async throws {
        isClosing = true
        defer { isClosing = false }
        await detach()
        try await database?.close()
        database = nil
    }
}
