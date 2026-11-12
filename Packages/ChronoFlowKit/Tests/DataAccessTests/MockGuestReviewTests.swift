import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct MockGuestReviewTests {
    @Test func firstReviewMintsHashedSecretWithoutCreatingAccountData() async throws {
        let store = MemoryMockStateStore()
        let source = guestMockSource(store: store)
        let review = try await source.reviewGuestTrip(guestReviewInput())
        let secret = try #require(review.identity.guestSecret)
        #expect(secret.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil)
        #expect(review.identity.inputRevision == 1 && review.identity.reviewRevision == 1)
        #expect(review.identity.sourceRevision == nil)
        #expect(review.price?.balance == 3 && review.price?.cost == 1 && review.price?.unlimited == false)
        #expect(review.canSave && review.saveBlockedReason == nil)
        let state = try #require(store.load())
        #expect(state.accounts.isEmpty && state.sessions.isEmpty && state.claims.isEmpty)
        #expect(state.guestDrafts?[review.identity.token]?.secretHash == MockGuestReview.hash(secret))
        let bytes = try JSONEncoder().encode(state)
        #expect(!String(decoding: bytes, as: UTF8.self).contains(secret))
    }

    @Test func laterReviewsReuseTokenAndNeverReturnSecretAgain() async throws {
        let source = guestMockSource()
        let first = try await source.reviewGuestTrip(guestReviewInput())
        let second = try await source.reviewGuestTrip(continuedGuestInput(first))
        #expect(second.identity.token == first.identity.token)
        #expect(second.identity.inputRevision == 2 && second.identity.reviewRevision == 2)
        #expect(second.identity.guestSecret == nil && second.canSave)
    }

    @Test(arguments: ["missing", "wrong", "token-as-secret", "foreign-device", "revision", "review-revision"])
    func missingWrongOrForeignPossessionExpires(kind: String) async throws {
        let source = guestMockSource()
        let first = try await source.reviewGuestTrip(guestReviewInput())
        var request = try continuedGuestInput(first)
        switch kind {
        case "missing": request.guestSecret = nil
        case "wrong": request.guestSecret = String(repeating: "0", count: 64)
        case "token-as-secret": request.guestSecret = first.identity.token
        case "foreign-device": request.deviceID = UUID().uuidString
        case "revision": request.identity?.inputRevision = 0
        default: request.identity?.reviewRevision = 0
        }
        await #expect(throws: DataFailure.reviewExpired) { try await source.reviewGuestTrip(request) }
    }

    @Test(arguments: ["known", "unknown", "foreign-device"])
    func freshReviewReusesOnlyAKnownDeviceSecret(kind: String) async throws {
        let source = guestMockSource()
        let first = try await source.reviewGuestTrip(guestReviewInput())
        var request = try guestReviewInput()
        request.guestSecret = first.identity.guestSecret
        if kind == "unknown" { request.guestSecret = String(repeating: "a", count: 64) }
        if kind == "foreign-device" { request.deviceID = UUID().uuidString }
        let second = try await source.reviewGuestTrip(request)
        #expect(second.identity.token != first.identity.token)
        if kind == "known" {
            #expect(second.identity.guestSecret == nil)
        } else {
            #expect(second.identity.guestSecret != nil && second.identity.guestSecret != first.identity.guestSecret)
        }
    }

    @Test(arguments: ["habitual_bed", "habitual_wake"])
    func guestSleepIsRequired(field: String) async throws {
        let source = guestMockSource()
        var request = try guestReviewInput()
        request.profile[field] = .null
        let expected = DataFailure.profileInvalid(fields: [
            "profile." + TripWizardErrors.camel(field): FieldMessage(key: "Check your bedtime and wake-up time.")
        ])
        await #expect(throws: expected) { try await source.reviewGuestTrip(request) }
    }

    @Test func sleepBecomesOverrideAndOnlyAgeAndShiftWorkPrompt() async throws {
        let store = MemoryMockStateStore()
        let source = guestMockSource(store: store)
        var request = try guestReviewInput()
        request.profile["habitual_bed"] = .string("01:00")
        request.profile["habitual_wake"] = .string("09:00")
        request.profile["age_band"] = nil
        request.profile["shift_work"] = nil
        request.profile["vte"] = .bool(true)
        let review = try await source.reviewGuestTrip(request)
        #expect(review.status == .needsAnswers && !review.canSave && review.saveBlockedReason == nil)
        #expect(review.price == nil && review.summary == nil)
        #expect(review.prompts.map(\.id) == ["age_band:::", "screening:shift_work::"])
        #expect(review.prompts.allSatisfy { $0.blocking })
        #expect(review.prompts[0].answer == ["age_band": .null])
        let draft = try #require(store.load()?.guestDrafts?[review.identity.token]?.draft)
        #expect(draft.input.override.use && draft.input.override.habitualBed == "01:00")
        #expect(draft.input.override.habitualWake == "09:00" && draft.profile["vte"] == nil)
        request.profile["age_band"] = .string("18_64")
        request.profile["shift_work"] = .bool(false)
        let ready = try await source.reviewGuestTrip(request)
        #expect(ready.canSave && ready.prompts.isEmpty)
    }

    @Test(arguments: ["age_band", "shift_work"])
    func exclusionGivesNoPlanOrPrompts(field: String) async throws {
        let source = guestMockSource()
        var request = try guestReviewInput()
        request.profile[field] = field == "age_band" ? .string("under_18") : .bool(true)
        let review = try await source.reviewGuestTrip(request)
        #expect(
            review.status == .noPlan && !review.canSave && review.prompts.isEmpty && review.summary == nil
                && review.price == nil)
    }

    @Test func pastArrivalUsesGuestMessage() async throws {
        let source = guestMockSource()
        var request = try guestReviewInput()
        request.input.outbound.legs[0].departLocal = "2026-11-01T11:00"
        request.input.outbound.legs[0].arriveLocal = "2026-11-02T06:00"
        await #expect(
            throws: DataFailure.validation(
                fields: [
                    "review": FieldMessage(key: "A new plan needs an upcoming arrival. Check your flight dates.")
                ], status: 422)
        ) { try await source.reviewGuestTrip(request) }
    }

    @Test func journeyErrorsMapToWizardFields() async throws {
        let source = guestMockSource()
        var request = try guestReviewInput()
        request.input.outbound.legs[0].toIata = "AMS"
        await #expect(
            throws: DataFailure.validation(
                fields: ["legs.0.toIata": FieldMessage(key: "Choose different departure and arrival airports.")],
                status: 422)
        ) { try await source.reviewGuestTrip(request) }
    }

    @Test func sixthDraftEvictsOldestForThatDeviceAcrossSecrets() async throws {
        let clock = MockClock()
        let store = MemoryMockStateStore()
        let source = guestMockSource(clock: clock, store: store)
        let first = try await source.reviewGuestTrip(guestReviewInput())
        for _ in 0..<5 {
            clock.advance(61)
            _ = try await source.reviewGuestTrip(guestReviewInput())
        }
        #expect(store.load()?.guestDrafts?.count == 5)
        await #expect(throws: DataFailure.reviewExpired) {
            try await source.reviewGuestTrip(continuedGuestInput(first))
        }
        var other = try guestReviewInput()
        other.deviceID = UUID().uuidString
        _ = try await source.reviewGuestTrip(other)
        #expect(store.load()?.guestDrafts?.count == 6)
    }

    @Test func expirySlidesForThirtyMinutesAndThenSecretIsUnknown() async throws {
        let clock = MockClock()
        let source = guestMockSource(clock: clock)
        let first = try await source.reviewGuestTrip(guestReviewInput())
        clock.advance(29 * 60)
        let second = try await source.reviewGuestTrip(continuedGuestInput(first))
        clock.advance(29 * 60)
        var request = try continuedGuestInput(second)
        request.guestSecret = first.identity.guestSecret
        let third = try await source.reviewGuestTrip(request)
        clock.advance(30 * 60)
        request.identity = third.identity
        await #expect(throws: DataFailure.reviewExpired) { try await source.reviewGuestTrip(request) }
        request.identity = nil
        let fresh = try await source.reviewGuestTrip(request)
        #expect(fresh.identity.guestSecret != nil && fresh.identity.guestSecret != first.identity.guestSecret)
    }

    @Test func guestRouteIgnoresBearerAndMemberCannotSaveGuestDraft() async throws {
        let store = MemoryMockStateStore()
        let clock = MockClock()
        let publicSource = MockDataSource(
            store: store, seed: MockServerState(), now: clock.now, sleep: { _ in },
            bearer: { throw DataFailure.unauthorized(status: 401) })
        let review = try await publicSource.reviewGuestTrip(guestReviewInput())
        #expect(review.price?.balance == 3)
        let member = try mockSource(store: store, seed: scenarioState())
        var state = try #require(store.load())
        state.accounts = try scenarioState().accounts
        store.save(state)
        _ = try await login(member)
        await #expect(throws: DataFailure.reviewExpired) {
            try await member.saveTrip(identity: ApiTripSaveInput(identity: review.identity))
        }
    }

    @Test func sixthAttemptThrottlesEvenInvalidRequestsAndResetsPerDevice() async throws {
        let clock = MockClock()
        let source = guestMockSource(clock: clock)
        var request = try guestReviewInput()
        request.profile = JSONObject()
        for _ in 0..<5 {
            await #expect(throws: (any Error).self) { try await source.reviewGuestTrip(request) }
        }
        request.deviceID = request.deviceID.uppercased()
        clock.advance(10)
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 50, status: 429)) {
            try await source.reviewGuestTrip(request)
        }
        request = try guestReviewInput()
        request.deviceID = UUID().uuidString
        _ = try await source.reviewGuestTrip(request)
        clock.advance(51)
        _ = try await source.reviewGuestTrip(guestReviewInput())
    }
}

func guestMockSource(clock: MockClock = MockClock(), store: any MockStateStore = MemoryMockStateStore())
    -> MockDataSource
{
    MockDataSource(store: store, seed: MockServerState(), now: clock.now, sleep: clock.sleep, id: clock.id)
}

func continuedGuestInput(_ review: ApiTripReview) throws -> ApiGuestTripReviewInput {
    var input = try guestReviewInput()
    input.identity = review.identity
    input.guestSecret = review.identity.guestSecret
    return input
}
