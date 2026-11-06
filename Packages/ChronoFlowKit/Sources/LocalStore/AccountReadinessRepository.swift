import AppCore
import GRDB

public struct AccountReadinessRepository: Sendable {
    private let database: AccountDatabase
    public init(database: AccountDatabase) { self.database = database }

    public func values(accountID: String) async throws -> StoredDataReadiness.Values {
        let id = try AccountID(accountID)
        guard await database.accountID == id else { throw StoreFailure.invalidAccountID }
        return try await database.observe { db in
            guard let account = try AccountRecord.fetchOne(db, key: id.rawValue) else { return nil }
            let policies = try SettingsRecord.fetchOne(db, key: "policies")?.value.decode(AccountPolicies.self)
            let gate: Gate
            if !account.hasVerifiedEmail {
                gate = .verify
            } else if let policies, policies.acceptedTermsVersion != policies.termsVersion {
                gate = .terms
            } else if !account.walkthroughSeen {
                gate = .walkthrough
            } else {
                gate = .app
            }
            return StoredAccountReadiness(accountID: id.rawValue, gate: gate, hasStoredData: account.syncedAt != nil)
        }
    }
}
