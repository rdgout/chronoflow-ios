import AppCore
import Foundation
import Testing
import TripWizard

struct GuestClaimStoreTests {
    @Test func providerNeedsALiveDraftAndItsKeychainSecret() async throws {
        let root = guestStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = WizardTestClock()
        let store = GuestWizardStore(applicationSupport: root, namespace: .mock, now: { clock.now })
        let secrets = MemoryGuestSecretStore()
        #expect(await store.claim(secrets: secrets) == nil)
        var draft = try await store.start()
        #expect(await store.claim(secrets: secrets) == nil)
        draft.form.identity = ApiReviewIdentity(token: "guest-token", inputRevision: 4, reviewRevision: 7)
        try await store.persist(draft)
        #expect(await store.claim(secrets: secrets) == nil)
        await secrets.set("secret", for: "guest-token")
        #expect(
            await store.claim(secrets: secrets)
                == GuestClaim(draftToken: "guest-token", inputRevision: 4, reviewRevision: 7, guestSecret: "secret"))
        clock.advance(1800)
        #expect(await store.claim(secrets: secrets) == nil)
    }

    @Test func expiredClaimReturnsToReadyAndInvalidatesTheReview() async throws {
        let root = guestStoreTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GuestWizardStore(applicationSupport: root, namespace: .mock)
        var draft = try await store.start()
        draft.form.identity = ApiReviewIdentity(token: "token", inputRevision: 1, reviewRevision: 2)
        draft.state.step = .checking
        draft.state.checkingAnswers = true
        draft.state.reviewedAt = Date()
        draft.state.profile["age_band"] = .string("18_64")
        try await store.persist(draft)
        try await store.reviewExpired(
            claim: GuestClaim(draftToken: "token", inputRevision: 1, reviewRevision: 2, guestSecret: "secret"))
        let recovered = try #require(await store.recover())
        #expect(recovered.state.step == .ready && recovered.state.returnToReady == true)
        #expect(recovered.state.checkingAnswers == nil && recovered.state.reviewedAt == nil)
        #expect(recovered.state.profile == draft.state.profile && recovered.form == draft.form)
        #expect(recovered.state.revision == draft.state.revision + 1)
    }
}
