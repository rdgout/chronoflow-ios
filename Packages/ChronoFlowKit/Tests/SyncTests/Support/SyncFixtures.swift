import AppCore
import Foundation
import GRDB
import LocalStore
import Sync

let syncAccount = "019a562b-8000-7000-8000-000000000001"
let syncOther = "019a562b-8000-7000-8000-000000000002"
let syncTrip = "019a562b-8000-7000-8000-000000000010"
let syncDate = Date(timeIntervalSince1970: 1_800_000_000)
let syncPolicies = AccountPolicies(termsVersion: "1", privacyVersion: "1")

func identity(_ id: String = syncAccount, verified: Bool = true) -> AccountIdentity {
    AccountIdentity(
        id: id, name: "Remote", email: "demo@example.com", hasVerifiedEmail: verified,
        policies: syncPolicies, walkthroughSeen: false)
}
func snapshot(_ id: String = syncAccount) -> AccountSnapshot {
    AccountSnapshot(
        id: id, name: "Remote", email: "demo@example.com", hasVerifiedEmail: true,
        settings: AccountSettings(
            bodyClock: JSONObject(["habitualBed": .string("23:00")]), sleepAnswered: true,
            preferences: JSONObject(["timeFormat": .string("24")]), reminders: JSONObject(), planCredits: JSONObject(),
            policies: syncPolicies), readiness: JSONObject(["ready": .bool(true)]), billing: JSONObject(),
        security: JSONObject())
}
func check(_ hash: String = "hash", status: CheckStatus? = .done) -> CheckOffChange {
    CheckOffChange(
        tripID: syncTrip, planInputHash: hash, type: .sleep, localDate: "2026-11-10", ordinal: 1, status: status)
}
func card(_ id: String = syncTrip, hash: String = "hash", version: String = "v1", keep: Bool = true) -> TripListItem {
    TripListItem(
        card: JSONObject(["id": .string(id), "departureUtc": .string("2026-11-10T10:00:00Z")]),
        planInputHash: hash, planStartUtc: "2026-11-09T10:00:00Z", planStartZone: "Europe/Amsterdam",
        planEndUtc: "2026-11-12T10:00:00Z", planEndDate: "2026-11-12", preparationDays: 1, keepOffline: keep,
        detailVersion: version)
}
func detail(_ hash: String = "hash", version: String = "v1", blocks: Bool = true) -> TripDetail {
    TripDetail(
        trip: JSONObject(["id": .string(syncTrip)]),
        plan: JSONObject([
            "meta": .object(["inputHash": .string(hash)]),
            "blocks": .array(
                blocks
                    ? [
                        .object([
                            "actionable": .bool(true),
                            "checkKey": .object([
                                "type": .string("sleep"), "localDate": .string("2026-11-10"), "ordinal": .number(1),
                            ]),
                        ])
                    ] : []),
        ]), notices: JSONObject(), timeline: JSONObject(),
        checkState: CheckState(planInputHash: hash, marks: [], days: []), detailVersion: version)
}

struct SyncStore {
    let database: AccountDatabase
    let root: URL
    let epoch: SyncEpoch
    init(id: String = syncAccount) async throws {
        root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/SyncTests/\(UUID().uuidString)")
        database = AccountDatabase(applicationSupport: root)
        try await database.open(accountID: id)
        epoch = SyncEpoch(accountID: try AccountID(id), generation: 1)
        try await AccountRepository(database: database).upsert(
            AccountRecord(id: id, name: "Local", email: "demo@example.com"))
        try await TripRepository(database: database).upsert(
            TripRecord(
                id: syncTrip, card: .encoding(card().card), currentInputHash: "hash",
                departureUtc: "2026-11-10T10:00:00Z"))
    }
    func close() async throws {
        try await database.close()
        try FileManager.default.removeItem(at: root)
    }
    func enqueue(_ change: OutboxChange, index: UInt8 = 0) async throws -> OutboxRecord {
        try await OutboxRepository(database: database).enqueue(
            change, now: syncDate, randomBytes: Array(repeating: index, count: 10))
    }
}

actor ScriptedSource: DataSource {
    var calls: [String] = []
    private var activeCalls = 0
    private(set) var maximumActiveCalls = 0
    var changes: [OutboxChange] = []
    var failures: [DataFailure?] = []
    var identityValue = identity()
    var snapshotValue = snapshot()
    var tripValues: [TripListItem] = [card()]
    var detailValue = detail()
    var failMethod: String?
    var methodFailure: DataFailure = .offline
    var receipts: [MutationReceipt] = []
    var hook: (@Sendable (String) async throws -> Void)?
    func configure(
        identity: AccountIdentity? = nil, snapshot: AccountSnapshot? = nil, trips: [TripListItem]? = nil,
        detail: TripDetail? = nil, failures: [DataFailure?] = [], failMethod: String? = nil,
        methodFailure: DataFailure = .offline, receipts: [MutationReceipt] = [],
        hook: (@Sendable (String) async throws -> Void)? = nil
    ) {
        if let identity { identityValue = identity }
        if let snapshot { snapshotValue = snapshot }
        if let trips { tripValues = trips }
        if let detail { detailValue = detail }
        self.failures = failures
        self.failMethod = failMethod
        self.methodFailure = methodFailure
        self.receipts = receipts
        self.hook = hook
    }
    private func record(_ method: String) async throws {
        calls.append(method)
        activeCalls += 1
        maximumActiveCalls = max(maximumActiveCalls, activeCalls)
        defer { activeCalls -= 1 }
        try await hook?(method)
        if method == failMethod { throw methodFailure }
    }
    func fetchIdentity() async throws -> AccountIdentity {
        try await record("identity")
        return identityValue
    }
    func fetchAccount() async throws -> AccountSnapshot {
        try await record("account")
        return snapshotValue
    }
    func fetchTrips() async throws -> [TripListItem] {
        try await record("trips")
        return tripValues
    }
    func fetchTripDetail(id: String) async throws -> TripDetail {
        try await record("detail")
        return detailValue
    }
    func send(_ change: OutboxChange) async throws -> MutationReceipt {
        changes.append(change)
        try await record("send")
        if !failures.isEmpty, let failure = failures.removeFirst() { throw failure }
        return receipts.isEmpty ? .acknowledged : receipts.removeFirst()
    }
    func passkeyOptions() throws -> ApiPasskeyChallenge { throw DataFailure.server(status: nil) }
    func passkeyLogin(_ input: ApiPasskeyLoginInput) throws -> SessionResult { throw DataFailure.server(status: nil) }
    func signIn(_ input: PasswordSignInInput) throws -> SignInResult { throw DataFailure.server(status: nil) }
    func completeTwoFactor(_ input: TwoFactorInput) throws -> SessionResult { throw DataFailure.server(status: nil) }
    func signUp(_ input: RegisterInput) throws -> SessionResult { throw DataFailure.server(status: nil) }
    func requestPasswordReset(email: String) throws { throw DataFailure.server(status: nil) }
    func resetPassword(_ input: ResetPasswordInput) throws { throw DataFailure.server(status: nil) }
    func verificationStatus() throws -> EmailVerificationStatus { throw DataFailure.server(status: nil) }
    func resendVerificationEmail() throws -> EmailVerificationStatus { throw DataFailure.server(status: nil) }
    func verifyEmail(_ input: SignedVerificationInput) throws -> EmailVerificationStatus {
        throw DataFailure.server(status: nil)
    }
    func signOut() throws { throw DataFailure.server(status: nil) }
}
