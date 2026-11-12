import Foundation

// Phase 20 in chronoflow-new docs/ui-plan/phase-20-mobile-api-passkey-management.md (branch
// feat/mobile-api-passkey-management). Not merged or deployed yet. The DTOs are hand-written until the contracts
// generator covers them.
public struct ApiPasskey: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var authenticator: String?
    public var createdAt: String
    public var lastUsedAt: String?

    public init(id: Int, name: String, authenticator: String? = nil, createdAt: String, lastUsedAt: String? = nil) {
        self.id = id
        self.name = name
        self.authenticator = authenticator
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct ApiPasskeyList: Codable, Sendable, Equatable {
    public var passkeys: [ApiPasskey]

    public init(passkeys: [ApiPasskey]) { self.passkeys = passkeys }
}

public struct ApiPasskeyRegistrationChallenge: Codable, Sendable, Equatable {
    public var challengeId: String
    public var options: ApiPasskeyCreationOptions

    public init(challengeId: String, options: ApiPasskeyCreationOptions) {
        self.challengeId = challengeId
        self.options = options
    }
}

public struct ApiPasskeyCreationOptions: Codable, Sendable, Equatable {
    public var challenge: String
    public var timeout: Int
    public var rp: ApiPasskeyRelyingParty
    public var user: ApiPasskeyUserEntity
    public var pubKeyCredParams: [ApiPasskeyCredentialParameters]
    public var authenticatorSelection: ApiPasskeyAuthenticatorSelection
    public var attestation: String
    public var excludeCredentials: [ApiPasskeyCredentialDescriptor]

    public init(
        challenge: String, timeout: Int = 60_000, rp: ApiPasskeyRelyingParty, user: ApiPasskeyUserEntity,
        pubKeyCredParams: [ApiPasskeyCredentialParameters] = [
            ApiPasskeyCredentialParameters(alg: -7), ApiPasskeyCredentialParameters(alg: -257),
        ],
        authenticatorSelection: ApiPasskeyAuthenticatorSelection = ApiPasskeyAuthenticatorSelection(),
        attestation: String = "none", excludeCredentials: [ApiPasskeyCredentialDescriptor] = []
    ) {
        self.challenge = challenge
        self.timeout = timeout
        self.rp = rp
        self.user = user
        self.pubKeyCredParams = pubKeyCredParams
        self.authenticatorSelection = authenticatorSelection
        self.attestation = attestation
        self.excludeCredentials = excludeCredentials
    }
}

public struct ApiPasskeyRelyingParty: Codable, Sendable, Equatable {
    public var id: String
    public var name: String

    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name ?? id
    }
}

public struct ApiPasskeyUserEntity: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var displayName: String

    public init(id: String, name: String, displayName: String? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName ?? name
    }
}

public struct ApiPasskeyCredentialParameters: Codable, Sendable, Equatable {
    public var type: CredentialType
    public var alg: Int

    public init(type: CredentialType = .publicKey, alg: Int) {
        self.type = type
        self.alg = alg
    }
}

public struct ApiPasskeyAuthenticatorSelection: Codable, Sendable, Equatable {
    public var requireResidentKey: Bool
    public var userVerification: String
    public var residentKey: String

    public init(
        requireResidentKey: Bool = true, userVerification: String = "required", residentKey: String = "required"
    ) {
        self.requireResidentKey = requireResidentKey
        self.userVerification = userVerification
        self.residentKey = residentKey
    }
}

public struct ApiPasskeyCredentialDescriptor: Codable, Sendable, Equatable {
    public var type: CredentialType
    public var id: String

    public init(id: String, type: CredentialType = .publicKey) {
        self.id = id
        self.type = type
    }
}

public struct ApiPasskeyAttestation: Codable, Sendable, Equatable {
    public var id: String
    public var rawId: String
    public var type: CredentialType
    public var response: ApiPasskeyAttestationResponse

    public init(id: String, rawId: String, type: CredentialType = .publicKey, response: ApiPasskeyAttestationResponse) {
        self.id = id
        self.rawId = rawId
        self.type = type
        self.response = response
    }
}

public struct ApiPasskeyAttestationResponse: Codable, Sendable, Equatable {
    public var clientDataJSON: String
    public var attestationObject: String
    public var transports: [String]?

    public init(clientDataJSON: String, attestationObject: String, transports: [String]? = nil) {
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
        self.transports = transports
    }
}

public struct ApiPasskeyRegistrationInput: Codable, Sendable, Equatable {
    public var challengeId: String
    public var name: String
    public var credential: ApiPasskeyAttestation

    public init(challengeId: String, name: String, credential: ApiPasskeyAttestation) {
        self.challengeId = challengeId
        self.name = name
        self.credential = credential
    }
}
