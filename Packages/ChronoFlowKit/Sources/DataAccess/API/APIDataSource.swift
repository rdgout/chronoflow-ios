import AppCore
import Foundation

public struct APIDataSource: DataSource {
    public let client: APIClient
    public init(client: APIClient) { self.client = client }
    private func publicPost<T: Encodable>(_ path: [String], _ input: T, timeout: TimeInterval = 15) throws
        -> APIEndpoint
    {
        APIEndpoint(
            method: "POST", path: path, access: .publicRoute, body: try JSONEncoder().encode(input), timeout: timeout)
    }
    public func passkeyOptions() async throws -> ApiPasskeyChallenge {
        let result: ApiPasskeyChallenge = try await client.request(
            APIEndpoint(method: "POST", path: ["auth", "passkey", "options"], access: .publicRoute))
        guard result.challengeId.count == 64, result.options.rpId == "app.chronoflow.net",
            result.options.timeout == 60_000,
            result.options.challenge.count == 43,
            result.options.challenge.unicodeScalars.allSatisfy(
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_").contains),
            Self.base64URL(result.options.challenge)?.count == 32
        else { throw DataFailure.server(status: 200) }
        return result
    }
    public static func base64URL(_ value: String) -> Data? {
        let normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4))
    }
    public func passkeyLogin(_ input: ApiPasskeyLoginInput) async throws -> SessionResult {
        try await client.request(publicPost(["auth", "passkey", "login"], input))
    }
    public func signIn(_ input: PasswordSignInInput) async throws -> SignInResult {
        try await client.request(publicPost(["auth", "login"], input))
    }
    public func completeTwoFactor(_ input: TwoFactorInput) async throws -> SessionResult {
        try await client.request(publicPost(["auth", "two-factor"], input))
    }
    public func signUp(_ input: RegisterInput) async throws -> SessionResult {
        try await client.request(publicPost(["auth", "register"], input, timeout: 90))
    }
    public func requestPasswordReset(email: String) async throws {
        try await client.requestNoContent(publicPost(["auth", "forgot-password"], ["email": email]))
    }
    public func resetPassword(_ input: ResetPasswordInput) async throws {
        try await client.requestNoContent(publicPost(["auth", "reset-password"], input))
    }
    public func verificationStatus() async throws -> EmailVerificationStatus {
        let identity = try await fetchIdentity()
        return EmailVerificationStatus(
            email: identity.email, hasVerifiedEmail: identity.hasVerifiedEmail, resendAfterSeconds: 0)
    }
    public func resendVerificationEmail() async throws -> EmailVerificationStatus {
        try await client.request(APIEndpoint(method: "POST", path: ["email", "verification-notification"]))
    }
    public func verifyEmail(_ input: SignedVerificationInput) async throws -> EmailVerificationStatus {
        try await client.request(
            APIEndpoint(method: "POST", path: ["email", "verify"], body: JSONEncoder().encode(input)))
    }
    public func signOut() async throws {
        try await client.requestNoContent(APIEndpoint(method: "POST", path: ["auth", "logout"], timeout: 3))
    }
    public func fetchIdentity() async throws -> AccountIdentity {
        try await client.request(APIEndpoint(path: ["users", "me"]))
    }
    public func fetchAccount() async throws -> AccountSnapshot {
        try await client.request(APIEndpoint(path: ["account"]))
    }
    public func fetchTrips() async throws -> [TripListItem] {
        struct List: Decodable, Sendable { let trips: [TripListItem] }
        let result: List = try await client.request(APIEndpoint(path: ["trips"]))
        guard result.trips.allSatisfy({ !$0.card.id.isEmpty && !$0.card.departureUtc.isEmpty }) else {
            throw DataFailure.server(status: 200)
        }
        return result.trips
    }
    public func fetchTripDetail(id: String) async throws -> TripDetailResponse {
        let data = try await client.requestData(APIEndpoint(path: ["trips", id]))
        let result: TripDetailResponse
        do { result = try TripDetailResponse(data: data) } catch { throw DataFailure.server(status: 200) }
        guard result.trip.id == id else { throw DataFailure.server(status: 200) }
        return result
    }
    public func send(_ change: OutboxChange) async throws -> MutationReceipt {
        switch change {
        case .checkOff(let input):
            struct Body: Encodable {
                let planInputHash: String
                let type: BlockType
                let localDate: String
                let ordinal: Int
                let status: CheckStatus?
                enum CodingKeys: String, CodingKey {
                    case type, ordinal, status
                    case planInputHash = "plan_input_hash"
                    case localDate = "local_date"
                }
                func encode(to encoder: any Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    try c.encode(planInputHash, forKey: .planInputHash)
                    try c.encode(type, forKey: .type)
                    try c.encode(localDate, forKey: .localDate)
                    try c.encode(ordinal, forKey: .ordinal)
                    try c.encode(status, forKey: .status)
                }
            }
            return .checks(
                try await client.request(
                    APIEndpoint(
                        method: "PUT", path: ["trips", input.tripID, "checks"],
                        body: JSONEncoder().encode(
                            Body(
                                planInputHash: input.planInputHash, type: input.type, localDate: input.localDate,
                                ordinal: input.ordinal, status: input.status)))))
        case .settings(let section, let patch):
            try SettingsPatchValidation.validate(section: section, patch: patch)
            let path = section == .bodyClock ? "body-clock" : section.rawValue
            return .account(
                try await client.request(
                    APIEndpoint(method: "PATCH", path: ["account", path], body: JSONEncoder().encode(patch))))
        case .profile(let input):
            return .identity(
                try await client.request(
                    APIEndpoint(method: "PATCH", path: ["users", "me"], body: JSONEncoder().encode(input))))
        case .policies(let version):
            let body: JSONObject = JSONObject(["accepted": .bool(true), "version": .string(version)])
            try await client.requestNoContent(
                APIEndpoint(method: "POST", path: ["terms", "acceptance"], body: JSONEncoder().encode(body)))
            return .acknowledged
        case .walkthrough:
            try await client.requestNoContent(APIEndpoint(method: "POST", path: ["walkthrough"]))
            return .acknowledged
        case .unsupported(let kind, _): throw DataFailure.unsupported(kind)
        }
    }
}
