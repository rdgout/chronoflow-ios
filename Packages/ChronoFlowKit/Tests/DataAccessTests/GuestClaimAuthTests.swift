import AppCore
import Auth
import Foundation
import Testing

@testable import DataAccess

@MainActor struct GuestClaimAuthTests {
    @Test(arguments: ["register", "password", "passkey"], [true, false])
    func requestUsesOnlyTheClaimFieldsForItsMethod(_ method: String, _ live: Bool) async throws {
        let response = try fixtureText("auth/session.json")
        let options = try fixtureText("auth/passkey-options.json")
        let server = StubServer { request in
            if request.url?.path.hasSuffix("/options") == true { return .init(200, options) }
            let body = try requestJSON(request)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(body["draft_token"] == (live ? .string("guest-token") : nil))
            #expect(body["guest_secret"] == (live ? .string("secret") : nil))
            #expect(body["input_revision"] == (live && method == "register" ? .number(4) : nil))
            #expect(body["review_revision"] == (live && method == "register" ? .number(7) : nil))
            #expect(body["device_id"] == .string("device") && body["device_name"] == .string("phone"))
            if method != "passkey" { #expect(body["password"] == .string("Password123!")) }
            if method == "register" { #expect(body["password_confirmation"] == .string("Password123!")) }
            return .init(200, response)
        }
        let session = ClaimAuthSession()
        let model = SignInModel(
            source: APIDataSource(client: try server.client()), session: session,
            deviceIdentity: { "device" }, deviceName: "phone",
            assertionProvider: DeterministicAssertionProvider { _ in
                Base64URL.assertion(
                    credentialID: Data([1]), clientDataJSON: Data([2]), authenticatorData: Data([3]),
                    signature: Data([4]), userHandle: nil)
            },
            claim: {
                live
                    ? GuestClaim(draftToken: "guest-token", inputRevision: 4, reviewRevision: 7, guestSecret: "secret")
                    : nil
            }, accepted: { _ in })
        model.editEmail("demo@example.com")
        model.editPassword("Password123!")
        if method == "register" {
            let registration = model.makeSignUpModel()
            registration.editPassword("Password123!")
            registration.editConfirmation("Password123!")
            #expect(await registration.submit(language: .en) == .accepted)
            #expect(registration.password.isEmpty && registration.confirmation.isEmpty)
        } else if method == "password" {
            await model.submitPassword()
            #expect(model.password.isEmpty)
        } else {
            await model.submitPasskey()
            #expect(model.password.isEmpty)
        }
        #expect(await session.count == 1)
        #expect(server.requests.count == (method == "passkey" ? 2 : 1))
    }

    @Test(arguments: ["expired", "validation-expired", "offline", "server"])
    func registrationFailureClearsBothPasswordsAndReturnsExpiry(_ failure: String) async throws {
        let server = StubServer { _ in
            switch failure {
            case "expired": return .init(422, #"{"code":"review_expired","message":"Review expired."}"#)
            case "validation-expired": return .init(422, try fixtureText("wizard/expired.json"))
            case "offline": return .init(error: URLError(.notConnectedToInternet))
            default: return .init(503)
            }
        }
        let expired = ClaimExpiryRecorder()
        let signIn = SignInModel(
            source: APIDataSource(client: try server.client()), session: ClaimAuthSession(),
            deviceIdentity: { "device" }, deviceName: "phone",
            claim: {
                GuestClaim(draftToken: "guest-token", inputRevision: 4, reviewRevision: 7, guestSecret: "secret")
            },
            guestReviewExpired: { _ in await expired.record() },
            accepted: { _ in Issue.record("Failed registration accepted") })
        let model = signIn.makeSignUpModel()
        model.editName("Traveller")
        model.editEmail("new@example.com")
        model.editPassword("Password123!")
        model.editConfirmation("Password123!")
        let outcome = await model.submit(language: .en)
        let isExpired = failure.hasSuffix("expired")
        #expect(outcome == (isExpired ? .guestReviewExpired : nil))
        #expect(await expired.count == (isExpired ? 1 : 0))
        #expect(model.password.isEmpty && model.confirmation.isEmpty && !model.form.busy)
        #expect(model.name == "Traveller" && model.email == "new@example.com")
        #expect(isExpired ? model.form.banner == nil : model.form.banner != nil)
    }
}

private actor ClaimAuthSession: SessionControlling {
    private(set) var count = 0
    func restore() -> SessionPresence { .signedOut }
    func signOut(discardPending: Bool, unauthorized: Bool) -> SignOutResult { .signedOut }
    func accept(_ result: SessionResult) { count += 1 }
}

private actor ClaimExpiryRecorder {
    private(set) var count = 0
    func record() { count += 1 }
}
