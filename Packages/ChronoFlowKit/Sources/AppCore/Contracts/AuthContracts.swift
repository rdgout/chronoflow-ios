import Foundation

public struct PasswordSignInInput: Codable, Sendable, Equatable {
    public var email: String
    public var password: String
    public var deviceID: String
    public var deviceName: String
    public var draftToken: String?
    public var guestSecret: String?
    enum CodingKeys: String, CodingKey {
        case email
        case password
        case deviceID = "device_id"
        case deviceName = "device_name"
        case draftToken = "draft_token"
        case guestSecret = "guest_secret"
    }

    public init(
        email: String, password: String, deviceID: String, deviceName: String, draftToken: String? = nil,
        guestSecret: String? = nil
    ) {
        self.email = email
        self.password = password
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.draftToken = draftToken
        self.guestSecret = guestSecret
    }
}

public struct RegisterInput: Codable, Sendable, Equatable {
    public var name: String
    public var email: String
    public var password: String
    public var passwordConfirmation: String
    public var deviceID: String
    public var deviceName: String
    public var language: AuthLanguage?
    public var draftToken: String?
    public var inputRevision: Int?
    public var reviewRevision: Int?
    public var guestSecret: String?
    enum CodingKeys: String, CodingKey {
        case name
        case email
        case password
        case passwordConfirmation = "password_confirmation"
        case deviceID = "device_id"
        case deviceName = "device_name"
        case language
        case draftToken = "draft_token"
        case inputRevision = "input_revision"
        case reviewRevision = "review_revision"
        case guestSecret = "guest_secret"
    }

    public init(
        name: String, email: String, password: String, passwordConfirmation: String, deviceID: String,
        deviceName: String, language: AuthLanguage? = nil, draftToken: String? = nil, inputRevision: Int? = nil,
        reviewRevision: Int? = nil, guestSecret: String? = nil
    ) {
        self.name = name
        self.email = email
        self.password = password
        self.passwordConfirmation = passwordConfirmation
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.language = language
        self.draftToken = draftToken
        self.inputRevision = inputRevision
        self.reviewRevision = reviewRevision
        self.guestSecret = guestSecret
    }
}

public struct ResetPasswordInput: Codable, Sendable, Equatable {
    public var token: String
    public var email: String
    public var password: String
    public var passwordConfirmation: String
    enum CodingKeys: String, CodingKey {
        case token
        case email
        case password
        case passwordConfirmation = "password_confirmation"
    }

    public init(token: String, email: String, password: String, passwordConfirmation: String) {
        self.token = token
        self.email = email
        self.password = password
        self.passwordConfirmation = passwordConfirmation
    }
}

public struct SignedVerificationInput: Codable, Sendable, Equatable {
    public var id: String
    public var hash: String
    public var expires: Int
    public var signature: String

    public init(id: String, hash: String, expires: Int, signature: String) {
        self.id = id
        self.hash = hash
        self.expires = expires
        self.signature = signature
    }
}

public struct EmailVerificationStatus: Codable, Sendable, Equatable {
    public var email: String
    public var hasVerifiedEmail: Bool
    public var resendAfterSeconds: Int

    public init(email: String, hasVerifiedEmail: Bool, resendAfterSeconds: Int) {
        self.email = email
        self.hasVerifiedEmail = hasVerifiedEmail
        self.resendAfterSeconds = resendAfterSeconds
    }
}

public enum AuthLanguage: String, Codable, Sendable { case en, nl }
public typealias AccountIdentity = SessionAccount

public enum SignInResult: Codable, Sendable, Equatable {
    case session(SessionResult)
    case twoFactor(challengeId: String)

    enum CodingKeys: String, CodingKey { case kind, challengeId }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "session": self = .session(try SessionResult(from: decoder))
        case "two-factor":
            let id = try c.decode(String.self, forKey: .challengeId)
            guard !id.isEmpty else { throw DataFailure.server(status: nil) }
            self = .twoFactor(challengeId: id)
        default: throw DataFailure.server(status: nil)
        }
    }
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .session(let result): try result.encode(to: encoder)
        case .twoFactor(let id):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("two-factor", forKey: .kind)
            try c.encode(id, forKey: .challengeId)
        }
    }
}

public struct TwoFactorInput: Codable, Sendable, Equatable {
    public enum Proof: Sendable, Equatable {
        case code(String)
        case recoveryCode(String)
    }
    public let challengeId: String
    public let proof: Proof
    public init(challengeId: String, proof: Proof) {
        self.challengeId = challengeId
        self.proof = proof
    }
    enum CodingKeys: String, CodingKey {
        case challengeId, code
        case recoveryCode = "recovery_code"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        challengeId = try c.decode(String.self, forKey: .challengeId)
        let code = try c.decodeIfPresent(String.self, forKey: .code)
        let recovery = try c.decodeIfPresent(String.self, forKey: .recoveryCode)
        switch (code, recovery) {
        case (.some(let value), nil): proof = .code(value)
        case (nil, .some(let value)): proof = .recoveryCode(value)
        default: throw DataFailure.server(status: nil)
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(challengeId, forKey: .challengeId)
        switch proof {
        case .code(let value): try c.encode(value, forKey: .code)
        case .recoveryCode(let value): try c.encode(value, forKey: .recoveryCode)
        }
    }
}
