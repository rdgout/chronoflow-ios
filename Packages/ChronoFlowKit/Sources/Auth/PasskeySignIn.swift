import AppCore
import Foundation

nonisolated public enum PasskeyFailure: Error, Sendable, Equatable {
    case canceled, invalidEncoding, unavailable, busy, alreadyRegistered
}

nonisolated public enum Base64URL {
    public static func encode(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func decode(_ value: String) throws -> Data {
        guard !value.isEmpty,
            value.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
            }), value.count % 4 != 1
        else {
            throw PasskeyFailure.invalidEncoding
        }
        let padded =
            value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let bytes = Data(base64Encoded: padded), encode(bytes) == value else {
            throw PasskeyFailure.invalidEncoding
        }
        return bytes
    }
    public static func assertion(
        credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userHandle: Data?
    ) -> ApiPasskeyAssertion {
        let id = encode(credentialID)
        return ApiPasskeyAssertion(
            id: id, rawId: id,
            response: ApiPasskeyAssertionResponse(
                clientDataJSON: encode(clientDataJSON), authenticatorData: encode(authenticatorData),
                signature: encode(signature),
                userHandle: userHandle.map(encode)))
    }
}

@MainActor public protocol PasskeyAssertionProviding: AnyObject {
    func assertion(for challenge: ApiPasskeyChallenge) async throws -> ApiPasskeyAssertion
}

@MainActor public final class DeterministicAssertionProvider: PasskeyAssertionProviding {
    private let provide: @MainActor (ApiPasskeyChallenge) async throws -> ApiPasskeyAssertion
    public init(
        _ provide: @escaping @MainActor (ApiPasskeyChallenge) async throws -> ApiPasskeyAssertion = { _ in
            throw PasskeyFailure.canceled
        }
    ) { self.provide = provide }
    public func assertion(for challenge: ApiPasskeyChallenge) async throws -> ApiPasskeyAssertion {
        try await provide(challenge)
    }
}

@MainActor public final class PasskeySignIn {
    private let source: any DataSource
    private let provider: any PasskeyAssertionProviding
    private let identity: @Sendable () async throws -> String
    private let deviceName: String
    private let claim: @Sendable () async -> GuestClaim?
    public init(
        source: any DataSource, provider: any PasskeyAssertionProviding,
        identity: @escaping @Sendable () async throws -> String, deviceName: String,
        claim: @escaping @Sendable () async -> GuestClaim? = { nil }
    ) {
        self.source = source
        self.provider = provider
        self.identity = identity
        self.deviceName = deviceName
        self.claim = claim
    }
    public func signIn() async throws -> SessionResult {
        let deviceID = try await identity()
        try Task.checkCancellation()
        let challenge = try await source.passkeyOptions()
        _ = try Base64URL.decode(challenge.options.challenge)
        guard !challenge.options.rpId.isEmpty else { throw PasskeyFailure.unavailable }
        try Task.checkCancellation()
        let assertion = try await provider.assertion(for: challenge)
        let claim = await claim()
        try Task.checkCancellation()
        return try await source.passkeyLogin(
            ApiPasskeyLoginInput(
                challengeId: challenge.challengeId, credential: assertion, deviceID: deviceID, deviceName: deviceName,
                draftToken: claim?.draftToken, guestSecret: claim?.guestSecret))
    }
}
