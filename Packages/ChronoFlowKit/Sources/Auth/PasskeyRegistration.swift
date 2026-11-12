import AppCore
import Foundation

extension Base64URL {
    public static func attestation(
        credentialID: Data, clientDataJSON: Data, attestationObject: Data, transports: [String]? = nil
    ) -> ApiPasskeyAttestation {
        let id = encode(credentialID)
        return ApiPasskeyAttestation(
            id: id, rawId: id,
            response: ApiPasskeyAttestationResponse(
                clientDataJSON: encode(clientDataJSON), attestationObject: encode(attestationObject),
                transports: transports))
    }
}

extension Base64URL {
    public static func excludedCredentialIDs(_ options: ApiPasskeyCreationOptions) throws -> [Data] {
        try options.excludeCredentials.map { try decode($0.id) }
    }
}

@MainActor public protocol PasskeyRegistrationProviding: AnyObject {
    func registration(for challenge: ApiPasskeyRegistrationChallenge) async throws -> ApiPasskeyAttestation
}

@MainActor public final class DeterministicRegistrationProvider: PasskeyRegistrationProviding {
    private let provide: @MainActor (ApiPasskeyRegistrationChallenge) async throws -> ApiPasskeyAttestation
    public init(
        _ provide: @escaping @MainActor (ApiPasskeyRegistrationChallenge) async throws -> ApiPasskeyAttestation = {
            challenge in
            Base64URL.attestation(
                credentialID: Data(("credential:" + challenge.options.challenge).utf8),
                clientDataJSON: Data(("client-data:" + challenge.options.challenge).utf8),
                attestationObject: Data(("attestation:" + challenge.options.challenge).utf8),
                transports: ["internal"])
        }
    ) { self.provide = provide }
    public func registration(for challenge: ApiPasskeyRegistrationChallenge) async throws -> ApiPasskeyAttestation {
        try await provide(challenge)
    }
}
