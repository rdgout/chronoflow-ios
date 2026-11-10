import AppCore
import CryptoKit
import Foundation

public struct MockServerAccount: Codable, Sendable, Equatable {
    public var snapshot: AccountSnapshot
    public var password: String
    public var twoFactorCode: String?
    public var recoveryCodes: Set<String>
    public var walkthroughSeen: Bool
    public var resendAvailableAt: TimeInterval
    public var trips: [TripListItem]
    public var details: [String: TripDetail]
    public init(
        snapshot: AccountSnapshot, password: String, twoFactorCode: String? = nil, recoveryCodes: Set<String> = [],
        walkthroughSeen: Bool = false, trips: [TripListItem] = [], details: [String: TripDetail] = [:]
    ) {
        self.snapshot = snapshot
        self.password = password
        self.twoFactorCode = twoFactorCode
        self.recoveryCodes = recoveryCodes
        self.walkthroughSeen = walkthroughSeen
        self.resendAvailableAt = 0
        self.trips = trips
        self.details = details
    }
    public var identity: AccountIdentity {
        AccountIdentity(
            id: snapshot.id, name: snapshot.name, email: snapshot.email, hasVerifiedEmail: snapshot.hasVerifiedEmail,
            policies: snapshot.settings.policies, walkthroughSeen: walkthroughSeen)
    }
}

public struct MockServerState: Codable, Sendable, Equatable {
    static var currentSchemaVersion: Int { 2 }
    var schemaVersion = Self.currentSchemaVersion
    var seedAnchor: String?
    public var accounts: [String: MockServerAccount]
    var sessions: [String: MockSession] = [:]
    var twoFactor: [String: MockTwoFactor] = [:]
    var passkeys: [String: MockPasskey] = [:]
    var resets: [String: MockReset] = [:]
    var rateWindows: [String: MockRateLimiter.Window] = [:]
    var mail: [MockMail] = []
    var wizardDrafts: [String: MockWizardDraft]?
    var wizardReceipts: [String: MockWizardReceipt]?
    var wizardPaidDirections: [String: [TripDirection]]?
    var wizardInputs: [String: ApiTripInputSnapshot]?
    var signingKey: Data
    public var claims: [String: MockClaim] = [:]
    public init(accounts: [MockServerAccount] = [], signingKey: Data = Data(UUID().uuidString.utf8)) {
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.snapshot.id, $0) })
        self.signingKey = signingKey
    }
}

public struct MockClaim: Codable, Sendable, Equatable {
    public let accountID: String
    public let tripID: String
    public let secret: String
    public init(accountID: String, tripID: String, secret: String) {
        self.accountID = accountID
        self.tripID = tripID
        self.secret = secret
    }
}
struct MockSession: Codable, Sendable, Equatable {
    let accountID: String
    let deviceID: String
    var expiresAt: TimeInterval
}
struct MockTwoFactor: Codable, Sendable, Equatable {
    let accountID: String
    let deviceID: String
    let expiresAt: TimeInterval
    var attempts: Int
}
struct MockPasskey: Codable, Sendable, Equatable {
    let challenge: ApiPasskeyChallenge
    let expiresAt: TimeInterval
}
struct MockReset: Codable, Sendable, Equatable {
    let token: String
    let expiresAt: TimeInterval
}

public protocol MockStateStore: Sendable {
    func load() throws -> MockServerState?
    func save(_ state: MockServerState) throws
}

public final class MemoryMockStateStore: MockStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: MockServerState?
    public init(_ state: MockServerState? = nil) { self.state = state }
    public func load() -> MockServerState? { lock.withLock { state } }
    public func save(_ state: MockServerState) { lock.withLock { self.state = state } }

    func update<T>(initial: MockServerState, _ change: (inout MockServerState) throws -> T) rethrows
        -> (T, MockServerState)
    {
        try lock.withLock {
            var candidate = state ?? initial
            let result = try change(&candidate)
            state = candidate
            return (result, candidate)
        }
    }
}

public struct FileMockStateStore: MockStateStore {
    public let url: URL
    public init(applicationSupport: URL) {
        url = applicationSupport.appendingPathComponent("ChronoFlowMock/Server/state.json")
    }
    public func load() throws -> MockServerState? {
        assert(!Thread.isMainThread)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(MockServerState.self, from: Data(contentsOf: url))
    }
    public func save(_ state: MockServerState) throws {
        assert(!Thread.isMainThread)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
        var directoryURL = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directoryURL.setResourceValues(values)
        #if os(iOS)
            for file in [directory, url] {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            }
        #endif
    }
}

extension AccountSnapshot {
    static func mockRegistration(id: String, name: String, email: String, language: AuthLanguage, now: Date) -> Self {
        let bodyFields = [
            "freeDayBed", "freeDayWake", "chronotype", "ageBand", "shiftWork",
            "caffeineHabit", "cupsFilterCoffee", "cupsTea", "cupsCola",
            "cupsEnergyDrink", "lightDevice", "blueBlockers", "blueBlockerMdfd",
        ]
        var body = Dictionary(uniqueKeysWithValues: bodyFields.map { ($0, JSONValue.null) })
        body.merge([
            "habitualBed": .string("23:00"), "habitualWake": .string("07:00"), "freeDayStatus": .string("unconfirmed"),
            "caffeineSensitive": .bool(false), "caffeineNonUserOptIn": .bool(false), "excludeCaffeine": .bool(false),
            "flightMovementBreaks": .bool(false),
            "invalidDrafts": .array([]),
        ]) { _, new in new }
        return Self(
            id: id, name: name, email: email, hasVerifiedEmail: false,
            settings: AccountSettings(
                bodyClock: JSONObject(body), sleepAnswered: false,
                preferences: JSONObject([
                    "hiddenCategories": .array([]), "showOptionalItems": .bool(false), "timeFormat": .string("24"),
                    "language": .string(language.rawValue),
                ]),
                reminders: JSONObject([
                    "light": .bool(true), "avoid": .bool(true), "caffeine": .bool(true), "winddown": .bool(false),
                    "leadMin": .number(30),
                ]),
                planCredits: JSONObject(["credits": .number(1), "unlimited": .bool(false)]),
                policies: AccountPolicies(
                    termsVersion: "1.0", privacyVersion: "1.0", acceptedTermsVersion: "1.0",
                    acceptedTermsAt: now.ISO8601Format())),
            readiness: MockSettings.readiness(JSONObject(body)),
            billing: JSONObject([
                "subscription": .object([
                    "tier": .string("free"), "status": .string("free"), "endsAt": .null, "renewsAt": .null,
                    "canResume": .bool(false), "canCancel": .bool(false), "paymentFailed": .bool(false),
                    "unlimited": .bool(false),
                ])
            ]),
            security: JSONObject([
                "twoFactorEnabled": .bool(false), "twoFactorConfirmedAt": .null,
                "passwordRules": .string(
                    "minlength: 12; required: lower; required: upper; required: digit; required: special;"),
            ]))
    }
}
