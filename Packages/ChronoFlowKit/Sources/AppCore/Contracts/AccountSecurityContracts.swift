import Foundation

public struct ApiTwoFactorSetup: Codable, Sendable, Equatable {
    public let secretKey: String
    public let otpauthUrl: String
    public init(secretKey: String, otpauthUrl: String) {
        self.secretKey = secretKey
        self.otpauthUrl = otpauthUrl
    }
}

public struct ApiRecoveryCodes: Codable, Sendable, Equatable {
    public let recoveryCodes: [String]
    public init(recoveryCodes: [String]) { self.recoveryCodes = recoveryCodes }
}

public enum AccountSecurityChange: Sendable, Equatable {
    case requestPasswordReset(email: String)
    case password(current: String, password: String, confirmation: String)
    case enableTwoFactor(current: String)
    case confirmTwoFactor(code: String)
    case disableTwoFactor(current: String)
    case revealRecoveryCodes(current: String)
    case regenerateRecoveryCodes(current: String)
    case listPasskeys
    case passkeyCreationOptions(current: String)
    case addPasskey(ApiPasskeyRegistrationInput)
    case removePasskey(id: Int, current: String)
}

public enum AccountSecurityResult: Sendable, Equatable {
    case changed
    case setup(ApiTwoFactorSetup)
    case codes(ApiRecoveryCodes)
    case snapshot(AccountSnapshot)
    case passkeys([ApiPasskey])
    case passkeyCreation(ApiPasskeyRegistrationChallenge)
    case passkeyAdded(ApiPasskey)
}
