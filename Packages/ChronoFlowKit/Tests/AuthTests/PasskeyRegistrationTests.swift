import AppCore
import Auth
import Foundation
import Testing

@Suite @MainActor struct PasskeyRegistrationTests {
    private let challenge = ApiPasskeyRegistrationChallenge(
        challengeId: "c1",
        options: ApiPasskeyCreationOptions(
            challenge: "Y2g", rp: ApiPasskeyRelyingParty(id: "app.chronoflow.net"),
            user: ApiPasskeyUserEntity(id: "dXNlcg", name: "demo@example.com")))

    @Test func attestationEncodesEveryBinaryFieldAsBase64URLAndRepeatsTheIDAsRawID() throws {
        let bytes = Data((0...255).map(UInt8.init))
        let attestation = Base64URL.attestation(
            credentialID: bytes, clientDataJSON: bytes, attestationObject: bytes, transports: ["internal", "hybrid"])
        let encoded = Base64URL.encode(bytes)
        #expect(attestation.id == encoded && attestation.rawId == encoded && attestation.type == .publicKey)
        #expect(attestation.response.clientDataJSON == encoded && attestation.response.attestationObject == encoded)
        #expect(attestation.response.transports == ["internal", "hybrid"])
        #expect(!encoded.contains("=") && !encoded.contains("+") && !encoded.contains("/"))
    }

    @Test func excludedCredentialIDsDecodeFromTheServerDescriptors() throws {
        let ids = [Data([1, 2, 3]), Data([251, 252, 253, 254])]
        var options = challenge.options
        options.excludeCredentials = ids.map { ApiPasskeyCredentialDescriptor(id: Base64URL.encode($0)) }
        #expect(try Base64URL.excludedCredentialIDs(options) == ids)
        #expect(try Base64URL.excludedCredentialIDs(challenge.options).isEmpty)
        options.excludeCredentials = [ApiPasskeyCredentialDescriptor(id: "not base64url!")]
        #expect(throws: (any Error).self) { try Base64URL.excludedCredentialIDs(options) }
    }

    @Test func deterministicProviderReturnsDecodableFieldsAndInjectedFailuresPropagate() async throws {
        let attestation = try await DeterministicRegistrationProvider().registration(for: challenge)
        for field in [
            attestation.id, attestation.rawId, attestation.response.clientDataJSON,
            attestation.response.attestationObject,
        ] {
            _ = try Base64URL.decode(field)
        }
        let canceled = DeterministicRegistrationProvider { _ in throw PasskeyFailure.canceled }
        await #expect(throws: PasskeyFailure.canceled) { try await canceled.registration(for: challenge) }
    }
}
