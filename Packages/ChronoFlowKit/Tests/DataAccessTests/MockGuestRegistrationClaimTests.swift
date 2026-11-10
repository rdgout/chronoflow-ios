import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct MockGuestRegistrationClaimTests {
    @Test func claimCreatesAccountProfileTripAndSpendsSignupCredits() async throws {
        let clock = MockClock()
        let store = MemoryMockStateStore()
        let source = guestMockSource(clock: clock, store: store)
        var input = try guestReviewInput()
        input.profile["habitual_bed"] = .string("23:30")
        input.profile["habitual_wake"] = .string("07:30")
        input.profile["chronotype"] = .string("late")
        let review = try await source.reviewGuestTrip(input)
        let session = try await source.signUp(guestRegistration(review))
        #expect(session.tripId == review.identity.token && !session.account.hasVerifiedEmail)
        let state = try #require(store.load())
        let account = try #require(state.accounts[session.account.id])
        #expect(state.accounts.count == 1 && state.sessions.count == 1 && state.mail.count == 1)
        #expect(account.trips.map(\.card.id) == [review.identity.token])
        #expect(account.details[review.identity.token]?.trip.id == review.identity.token)
        #expect(account.snapshot.settings.bodyClock["habitualBed"] == .string("23:30"))
        #expect(account.snapshot.settings.bodyClock["habitualWake"] == .string("07:30"))
        #expect(account.snapshot.settings.bodyClock["chronotype"] == .string("late"))
        #expect(account.snapshot.settings.bodyClock["ageBand"] == .string("18_64"))
        #expect(account.snapshot.settings.sleepAnswered)
        #expect(account.snapshot.settings.planCredits["credits"] == .number(2))
        #expect(state.guestDrafts?[review.identity.token] == nil)
        let receipt = try #require(state.claims[review.identity.token])
        #expect(receipt.accountID == session.account.id && receipt.tripID == review.identity.token)
        #expect(receipt.expiresAt == clock.now().timeIntervalSince1970 + 7 * 86400)
        #expect(receipt.deviceID == input.deviceID)
        #expect(
            state.wizardInputs?[session.account.id + ":" + review.identity.token]?.input.override.habitualBed == "23:30"
        )
        let stored = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(!stored.contains(try #require(review.identity.guestSecret)))
    }

    @Test func freeTripKeepsThreeSignupCredits() async throws {
        let store = MemoryMockStateStore()
        let source = guestMockSource(store: store)
        var input = try guestReviewInput()
        input.input.outbound.legs[0].toIata = "DXB"
        input.input.outbound.legs[0].arriveLocal = "2026-11-10T20:00"
        let review = try await source.reviewGuestTrip(input)
        #expect(review.price.cost == 0 && review.canSave)
        let session = try await source.signUp(guestRegistration(review))
        #expect(store.load()?.accounts[session.account.id]?.snapshot.settings.planCredits["credits"] == .number(3))
    }

    @Test(arguments: [
        "input-revision", "review-revision", "wrong-secret", "missing-secret", "foreign-device", "unknown-token",
        "missing-token", "missing-review-revision", "missing-input-revision", "expired",
    ])
    func staleClaimsCreateNothing(kind: String) async throws {
        let clock = MockClock()
        let store = MemoryMockStateStore()
        let source = guestMockSource(clock: clock, store: store)
        let review = try await source.reviewGuestTrip(guestReviewInput())
        var input = try guestRegistration(review)
        switch kind {
        case "input-revision": input.inputRevision = 5
        case "review-revision": input.reviewRevision = 4
        case "wrong-secret": input.guestSecret = String(repeating: "0", count: 64)
        case "missing-secret": input.guestSecret = nil
        case "foreign-device": input.deviceID = UUID().uuidString
        case "unknown-token": input.draftToken = UUID().uuidString
        case "missing-token": input.draftToken = nil
        case "missing-review-revision": input.reviewRevision = nil
        case "missing-input-revision": input.inputRevision = nil
        default: clock.advance(31 * 60)
        }
        await #expect(throws: expiredGuestClaim) { try await source.signUp(input) }
        let state = try #require(store.load())
        #expect(state.accounts.isEmpty && state.sessions.isEmpty && state.claims.isEmpty && state.mail.isEmpty)
        #expect(state.wizardInputs == nil && state.wizardPaidDirections == nil)
    }

    @Test func blockedReviewCannotCreateAccount() async throws {
        let store = MemoryMockStateStore()
        let source = guestMockSource(store: store)
        var input = try guestReviewInput()
        input.profile["shift_work"] = nil
        let review = try await source.reviewGuestTrip(input)
        #expect(!review.canSave)
        await #expect(throws: expiredGuestClaim) { try await source.signUp(guestRegistration(review)) }
        #expect(store.load()?.accounts.isEmpty == true && store.load()?.claims.isEmpty == true)
    }

    @Test func claimedDraftCannotCreateAnotherAccount() async throws {
        let store = MemoryMockStateStore()
        let source = guestMockSource(store: store)
        let review = try await source.reviewGuestTrip(guestReviewInput())
        var input = try guestRegistration(review)
        _ = try await source.signUp(input)
        input.email = "second@example.com"
        await #expect(throws: expiredGuestClaim) { try await source.signUp(input) }
        #expect(store.load()?.accounts.count == 1 && store.load()?.claims.count == 1)
    }

    @Test func accountFieldsStillValidateBeforeAnyClaimEffects() async throws {
        let store = MemoryMockStateStore()
        let source = guestMockSource(store: store)
        let review = try await source.reviewGuestTrip(guestReviewInput())
        var input = try guestRegistration(review)
        input.passwordConfirmation = "different"
        await #expect(
            throws: DataFailure.validation(
                fields: ["password_confirmation": FieldMessage(key: "The passwords don't match yet.")], status: 422)
        ) { try await source.signUp(input) }
        #expect(store.load()?.accounts.isEmpty == true && store.load()?.claims.isEmpty == true)
    }

    @Test func replayReturnsSameTripAndAccountWithoutAnotherChargeAfterReload() async throws {
        let clock = MockClock()
        let store = MemoryMockStateStore()
        let source = guestMockSource(clock: clock, store: store)
        let review = try await source.reviewGuestTrip(guestReviewInput())
        let input = try guestRegistration(review)
        let first = try await source.signUp(input)
        let restored = guestMockSource(clock: clock, store: store)
        var retry = input
        retry.email = " TRAVELLER@example.com "
        let second = try await restored.signUp(retry)
        #expect(second.tripId == first.tripId && second.account.id == first.account.id && second.token != first.token)
        let state = try #require(store.load())
        #expect(
            state.accounts.count == 1 && state.claims.count == 1 && state.sessions.count == 1 && state.mail.count == 1)
        #expect(state.sessions[first.token] == nil)
        #expect(state.accounts[first.account.id]?.trips.count == 1)
        #expect(state.accounts[first.account.id]?.snapshot.settings.planCredits["credits"] == .number(2))
    }

    @Test(arguments: ["password", "secret", "two-factor"])
    func retryMustProveAccountAndPossession(kind: String) async throws {
        let store = MemoryMockStateStore()
        let source = guestMockSource(store: store)
        let review = try await source.reviewGuestTrip(guestReviewInput())
        var input = try guestRegistration(review)
        let first = try await source.signUp(input)
        switch kind {
        case "password":
            input.password = "AnotherPassword12!"
            input.passwordConfirmation = input.password
        case "secret": input.guestSecret = String(repeating: "1", count: 64)
        default:
            var state = try #require(store.load())
            state.accounts[first.account.id]?.twoFactorCode = "123456"
            store.save(state)
        }
        await #expect(
            throws: DataFailure.validation(
                fields: ["email": FieldMessage(key: "This email address is already in use.")], status: 422)
        ) { try await source.signUp(input) }
        #expect(store.load()?.accounts.count == 1 && store.load()?.sessions.count == 1)
    }

    @Test func receiptKeepsDeviceSecretKnownForFreshReview() async throws {
        let source = guestMockSource()
        let review = try await source.reviewGuestTrip(guestReviewInput())
        _ = try await source.signUp(guestRegistration(review))
        var input = try guestReviewInput()
        input.guestSecret = review.identity.guestSecret
        let fresh = try await source.reviewGuestTrip(input)
        #expect(fresh.identity.guestSecret == nil && fresh.identity.token != review.identity.token)
    }

    @Test(arguments: ["matching", "no-claim", "wrong-secret", "missing-secret", "other-account", "expired"])
    func loginReplaysOnlyLiveMatchingReceipt(kind: String) async throws {
        let clock = MockClock()
        let store = MemoryMockStateStore()
        let source = guestMockSource(clock: clock, store: store)
        let review = try await source.reviewGuestTrip(guestReviewInput())
        let registration = try guestRegistration(review)
        _ = try await source.signUp(registration)
        var input = PasswordSignInInput(
            email: registration.email, password: registration.password, deviceID: UUID().uuidString,
            deviceName: "Test phone",
            draftToken: review.identity.token, guestSecret: review.identity.guestSecret)
        switch kind {
        case "no-claim":
            input.draftToken = nil
            input.guestSecret = nil
        case "wrong-secret": input.guestSecret = String(repeating: "2", count: 64)
        case "missing-secret": input.guestSecret = nil
        case "other-account":
            var other = registration
            other.email = "stranger@example.com"
            other.draftToken = nil
            other.guestSecret = nil
            other.inputRevision = nil
            other.reviewRevision = nil
            _ = try await source.signUp(other)
            input.email = other.email
        case "expired": clock.advance(7 * 86400)
        default: break
        }
        let restored = guestMockSource(clock: clock, store: store)
        guard case .session(let session) = try await restored.signIn(input) else {
            Issue.record("Expected password session")
            return
        }
        #expect(session.tripId == (kind == "matching" ? review.identity.token : nil))
    }

    @Test func plainRegistrationLeavesGuestDraftAndSignupCredits() async throws {
        let store = MemoryMockStateStore()
        let source = guestMockSource(store: store)
        let review = try await source.reviewGuestTrip(guestReviewInput())
        let session = try await source.signUp(registration())
        #expect(session.tripId == nil)
        let state = try #require(store.load())
        #expect(state.guestDrafts?[review.identity.token] != nil && state.claims.isEmpty)
        #expect(state.accounts[session.account.id]?.trips.isEmpty == true)
        #expect(state.accounts[session.account.id]?.snapshot.settings.planCredits["credits"] == .number(3))
    }

    @Test func legacyClaimDecodesAndReencodesWithoutPlaintextSecret() throws {
        let old = Data(#"{"accountID":"owner","tripID":"trip","secret":"legacy-secret"}"#.utf8)
        let claim = try JSONDecoder().decode(MockClaim.self, from: old)
        #expect(claim.secretHash == MockGuestReview.hash("legacy-secret"))
        let stored = String(decoding: try JSONEncoder().encode(claim), as: UTF8.self)
        #expect(!stored.contains("legacy-secret"))
    }
}

private var expiredGuestClaim: DataFailure {
    .validation(
        fields: ["review_expired": FieldMessage(key: "Review your trip again before creating your account.")],
        status: 422)
}

func guestRegistration(_ review: ApiTripReview) throws -> RegisterInput {
    var input = registration("traveller@example.com")
    input.deviceID = try guestReviewInput().deviceID
    input.draftToken = review.identity.token
    input.inputRevision = review.identity.inputRevision
    input.reviewRevision = review.identity.reviewRevision
    input.guestSecret = review.identity.guestSecret
    return input
}
