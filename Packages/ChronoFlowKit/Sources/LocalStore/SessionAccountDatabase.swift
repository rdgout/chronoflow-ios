import AppCore
import Foundation
import GRDB

public actor SessionAccountDatabase: SessionAccountStore {
    private let applicationSupport: URL
    private let namespace: StorageNamespace
    private var database: AccountDatabase?
    private let detach: @Sendable () async -> Void

    public init(applicationSupport: URL, namespace: StorageNamespace, detach: @escaping @Sendable () async -> Void = {})
    {
        self.applicationSupport = applicationSupport
        self.namespace = namespace
        self.detach = detach
    }

    public func activeDatabase() -> AccountDatabase? { database }

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
            record.walkthroughSeen = account.walkthroughSeen
            try record.save(db)
            let data = try JSONEncoder().encode(account.policies)
            try SettingsRecord(section: "policies", value: JSONDocument(String(decoding: data, as: UTF8.self))).save(db)
        }
    }

    public func close() async throws {
        await detach()
        try await database?.close()
        database = nil
    }
}
