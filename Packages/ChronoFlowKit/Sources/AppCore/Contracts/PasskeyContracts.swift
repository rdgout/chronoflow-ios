import Foundation

public struct ApiPasskeyChallenge: Codable, Sendable, Equatable {
    public var challengeId: String
    public var options: ApiPasskeyRequestOptions

    public init(challengeId: String, options: ApiPasskeyRequestOptions) {
        self.challengeId = challengeId
        self.options = options
    }
}

public struct ApiPasskeyRequestOptions: Codable, Sendable, Equatable {
    public var challenge: String
    public var rpId: String
    public var timeout: Int
    public var userVerification: UserVerification
    public var allowCredentials: [EmptyCredential]

    public init(
        challenge: String, rpId: String, timeout: Int, userVerification: UserVerification = .required,
        allowCredentials: [EmptyCredential] = []
    ) {
        self.challenge = challenge
        self.rpId = rpId
        self.timeout = timeout
        self.userVerification = userVerification
        self.allowCredentials = allowCredentials
    }
}

public struct ApiPasskeyLoginInput: Codable, Sendable, Equatable {
    public var challengeId: String
    public var credential: ApiPasskeyAssertion
    public var deviceID: String
    public var deviceName: String
    public var draftToken: String?
    public var guestSecret: String?
    enum CodingKeys: String, CodingKey {
        case challengeId
        case credential
        case deviceID = "device_id"
        case deviceName = "device_name"
        case draftToken = "draft_token"
        case guestSecret = "guest_secret"
    }

    public init(
        challengeId: String, credential: ApiPasskeyAssertion, deviceID: String, deviceName: String,
        draftToken: String? = nil, guestSecret: String? = nil
    ) {
        self.challengeId = challengeId
        self.credential = credential
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.draftToken = draftToken
        self.guestSecret = guestSecret
    }
}

public struct ApiPasskeyAssertion: Codable, Sendable, Equatable {
    public var id: String
    public var rawId: String
    public var type: CredentialType
    public var response: ApiPasskeyAssertionResponse

    public init(id: String, rawId: String, type: CredentialType = .publicKey, response: ApiPasskeyAssertionResponse) {
        self.id = id
        self.rawId = rawId
        self.type = type
        self.response = response
    }
}

public struct ApiPasskeyAssertionResponse: Codable, Sendable, Equatable {
    public var clientDataJSON: String
    public var authenticatorData: String
    public var signature: String
    public var userHandle: String?

    public init(clientDataJSON: String, authenticatorData: String, signature: String, userHandle: String? = nil) {
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userHandle = userHandle
    }
}

public enum UserVerification: String, Codable, Sendable { case required }
public enum CredentialType: String, Codable, Sendable { case publicKey = "public-key" }
public enum EmptyCredential: Codable, Sendable, Equatable {
    public init(from decoder: any Decoder) throws { throw DataFailure.server(status: nil) }
    public func encode(to encoder: any Encoder) throws { switch self {} }
}
