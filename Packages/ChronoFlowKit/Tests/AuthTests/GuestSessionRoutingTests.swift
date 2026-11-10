import AppCore
import Auth
import Foundation
import Testing

@MainActor struct GuestSessionRoutingTests {
    @Test(arguments: [AuthenticationMethod.signUp, .password, .passkey, .twoFactor])
    func acceptedPreservesTheSessionAndAuthenticationMethod(_ method: AuthenticationMethod) async throws {
        let session = AuthTestSession()
        var accepted: [(SessionResult, AuthenticationMethod)] = []
        let model = SignInModel(
            source: try authTestSource(twoFactor: method == .twoFactor), session: session,
            deviceIdentity: { "0199a3c0-0000-7000-8000-000000000001" }, deviceName: "phone",
            assertionProvider: DeterministicAssertionProvider { _ in
                Base64URL.assertion(
                    credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]),
                    signature: Data([4]), userHandle: nil)
            }, accepted: { accepted.append(($0, $1)) })
        model.editEmail("demo@example.com")
        model.editPassword("Password123!")
        switch method {
        case .signUp:
            let registration = model.makeSignUpModel()
            registration.editName("Traveller")
            registration.editEmail("new@example.com")
            registration.editPassword("Password123!")
            registration.editConfirmation("Password123!")
            #expect(await registration.submit(language: .en) == .accepted)
        case .passkey: await model.submitPasskey()
        case .password: await model.submitPassword()
        case .twoFactor:
            await model.submitPassword()
            #expect(accepted.isEmpty)
            let challenge = try #require(model.twoFactor)
            challenge.editCode("123456")
            await challenge.submit()
            #expect(challenge.code.isEmpty && model.navigation.challengeID == nil)
        }
        #expect(accepted.count == 1 && accepted.first?.1 == method)
        #expect(await session.accepted == accepted.map(\.0))
    }
}
