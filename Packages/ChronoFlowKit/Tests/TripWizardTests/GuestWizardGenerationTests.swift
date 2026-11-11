import AppCore
import Foundation
import Testing
import TripWizard

@Suite struct GuestWizardGenerationTests {
    @Test func firstCallMintsSecretAndUsesSleepAnswersAndDeviceWithoutAccountEffects() async throws {
        let fixture = try GuestGenerationFixture()
        let minted = try guestReview(token: "first", secret: "minted")
        await fixture.source.queueReviews([.success(minted)])
        var input = try guestGenerationInput()
        input.profile?["pregnancy"] = .bool(true)
        let result = try await fixture.service.review(instance: "wizard", input: input)
        let sent = try #require(await fixture.source.guestInputs.first)
        #expect(sent.identity == nil && sent.guestSecret == nil)
        #expect(sent.profile["habitual_bed"] == .string("23:00"))
        #expect(sent.profile["habitual_wake"] == .string("07:00"))
        #expect(sent.profile["chronotype"] == .string("intermediate"))
        #expect(sent.profile["age_band"] == .string("18_64") && sent.profile["shift_work"] == .bool(false))
        #expect(sent.profile["pregnancy"] == nil)
        #expect(sent.deviceID == (try await fixture.device.identity()))
        #expect(await fixture.secrets.get(for: "first") == "minted")
        #expect(result.review.identity.guestSecret == nil && result.input.identity?.guestSecret == nil)
        #expect(
            result.input.input.return == nil && result.input.input.tripEndKind == "one_way"
                && !result.input.input.override.use)
        #expect(await fixture.source.operations == ["guestReview"])
        #expect(await fixture.persistence.writes == 1)
        await #expect(throws: DataFailure.self) {
            try await fixture.service.save(
                TripGenerationState(instance: "wizard", input: input),
                didCreate: { _ in Issue.record("guest must not save") })
        }
    }

    @Test func knownSecretIsReusedAndANewTokenRotatesIt() async throws {
        let fixture = try GuestGenerationFixture()
        await fixture.secrets.set("known", for: "old")
        var input = try guestGenerationInput()
        input.identity = ApiReviewIdentity(token: "old", inputRevision: 2, reviewRevision: 3)
        await fixture.source.queueReviews([
            .success(try guestReview(token: "old")), .success(try guestReview(token: "new", secret: "rotated")),
        ])
        let first = try await fixture.service.review(instance: "wizard", input: input)
        #expect(await fixture.source.guestInputs.first?.guestSecret == "known")
        #expect(await fixture.secrets.get(for: "old") == "known")
        _ = try await fixture.service.review(instance: "wizard", input: first.input)
        #expect(await fixture.secrets.get(for: "old") == nil)
        #expect(await fixture.secrets.get(for: "new") == "rotated")
    }

    @Test func expiryRetriesOnceWithoutIdentityAndRetainsKnownSecretForNewToken() async throws {
        let fixture = try GuestGenerationFixture()
        await fixture.secrets.set("known", for: "old")
        var input = try guestGenerationInput()
        input.identity = ApiReviewIdentity(token: "old", inputRevision: 2, reviewRevision: 3)
        await fixture.source.queueReviews([.failure(.reviewExpired), .success(try guestReview(token: "fresh"))])
        let result = try await fixture.service.review(instance: "wizard", input: input)
        let sent = await fixture.source.guestInputs
        #expect(sent.count == 2 && sent[0].identity == input.identity && sent[1].identity == nil)
        #expect(sent[0].guestSecret == "known" && sent[1].guestSecret == "known")
        #expect(result.input.identity?.token == "fresh")
        #expect(await fixture.secrets.get(for: "fresh") == "known")
        #expect(await fixture.secrets.get(for: "old") == nil)
    }

    @Test func secondExpirySurfacesAndFirstCallExpiryIsNotRetried() async throws {
        let fixture = try GuestGenerationFixture()
        var input = try guestGenerationInput()
        input.identity = ApiReviewIdentity(token: "old", inputRevision: 1, reviewRevision: 1)
        await fixture.source.queueReviews([.failure(.reviewExpired), .failure(.reviewExpired)])
        await #expect(throws: DataFailure.reviewExpired) {
            try await fixture.service.review(instance: "wizard", input: input)
        }
        #expect(await fixture.source.guestInputs.count == 2)
        input.identity = nil
        await fixture.source.queueReviews([.failure(.reviewExpired)])
        await #expect(throws: DataFailure.reviewExpired) {
            try await fixture.service.review(instance: "wizard", input: input)
        }
        #expect(await fixture.source.guestInputs.count == 3)
    }

    @Test(arguments: [DataFailure.offline, .throttled(retryAfterSeconds: 42, status: 429)])
    func failuresSurfaceWithoutRetry(_ failure: DataFailure) async throws {
        let fixture = try GuestGenerationFixture()
        await fixture.source.queueReviews([.failure(failure)])
        await #expect(throws: failure) {
            try await fixture.service.review(instance: "wizard", input: guestGenerationInput())
        }
        #expect(await fixture.source.guestInputs.count == 1)
    }

    @Test func discardDuringRequestDeletesMintedSecretAndDropsResult() async throws {
        let fixture = try GuestGenerationFixture()
        let gate = GenerationGate()
        await fixture.source.configure(beforeReview: { await gate.wait() })
        await fixture.source.queueReviews([.success(try guestReview(token: "late", secret: "late-secret"))])
        let request = Task { try await fixture.service.review(instance: "wizard", input: guestGenerationInput()) }
        await fixture.source.waitForGuestReviews(1)
        await fixture.service.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(await fixture.secrets.get(for: "late") == nil)
        await #expect(throws: CancellationError.self) {
            try await fixture.service.review(instance: "wizard", input: guestGenerationInput())
        }
    }

    @Test func cancelledReviewDoesNotRetryExpiryAndAllowsNextCheck() async throws {
        let fixture = try GuestGenerationFixture()
        let gate = GenerationGate()
        await fixture.source.configure(beforeReview: { await gate.wait() })
        await fixture.source.queueReviews([.failure(.reviewExpired)])
        var input = try guestGenerationInput()
        input.identity = ApiReviewIdentity(token: "old", inputRevision: 1)
        let snapshot = input
        let request = Task { try await fixture.service.review(instance: "check", input: snapshot) }
        await fixture.source.waitForGuestReviews(1)
        await fixture.service.cancelReviews(instance: "check")
        await gate.open()
        do {
            _ = try await request.value
            Issue.record("cancelled review returned")
        } catch {}
        #expect(await fixture.source.guestInputs.count == 1)
        await fixture.source.configure()
        await fixture.source.queueReviews([.success(try guestReview(token: "next", secret: "secret"))])
        _ = try await fixture.service.review(instance: "next-check", input: guestGenerationInput())
        #expect(await fixture.secrets.get(for: "next") == "secret")
    }

    @Test func staleTokenDoesNotRetryAfterAnotherReviewChangesIt() async throws {
        let fixture = try GuestGenerationFixture()
        let gate = GenerationGate()
        let fresh = try guestReview(token: "fresh", secret: "secret")
        await fixture.source.handleGuestReview { input in
            if input.identity?.token == "old" {
                await gate.wait()
                throw DataFailure.reviewExpired
            }
            return fresh
        }
        var old = try guestGenerationInput()
        old.identity = ApiReviewIdentity(token: "old", inputRevision: 1)
        let snapshot = old
        let request = Task { try await fixture.service.review(instance: "wizard", input: snapshot) }
        await fixture.source.waitForGuestReviews(1)
        _ = try await fixture.service.review(instance: "wizard", input: guestGenerationInput())
        await gate.open()
        await #expect(throws: DataFailure.reviewExpired) { try await request.value }
        #expect(await fixture.source.guestInputs.count == 2)
        #expect(await fixture.secrets.get(for: "fresh") == "secret")
    }

    @Test func expiryInsideValidationUsesSharedErrorMapping() async throws {
        let fixture = try GuestGenerationFixture()
        var input = try guestGenerationInput()
        input.identity = ApiReviewIdentity(token: "old", inputRevision: 1)
        await fixture.source.queueReviews([
            .failure(
                .validation(fields: ["review_expired": FieldMessage(key: "Review your trip again.")], status: 422)),
            .success(try guestReview(token: "fresh", secret: "secret")),
        ])
        let result = try await fixture.service.review(instance: "wizard", input: input)
        #expect(result.review.identity.token == "fresh")
        #expect(await fixture.source.guestInputs.count == 2)
    }

    @Test func discardWhileSecretIsBeingStoredCleansItUp() async throws {
        let fixture = try GuestGenerationFixture()
        let secrets = PausedGuestSecrets()
        let service = GuestWizardGeneration(source: fixture.source, secrets: secrets, deviceIdentity: fixture.device)
        await fixture.source.queueReviews([.success(try guestReview(token: "late", secret: "secret"))])
        let request = Task { try await service.review(instance: "wizard", input: guestGenerationInput()) }
        await secrets.stored.wait()
        await service.cancel()
        await secrets.release.open()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(await secrets.get(for: "late") == nil)
    }

    @Test func duplicateReviewsShareOneRequestAndTimeoutIsThirtySeconds() async throws {
        let fixture = try GuestGenerationFixture()
        let gate = GenerationGate()
        await fixture.source.configure(beforeReview: { await gate.wait() })
        await fixture.source.queueReviews([.success(try guestReview(token: "shared", secret: "secret"))])
        let input = try guestGenerationInput()
        async let first = fixture.service.review(instance: "same", input: input)
        async let second = fixture.service.review(instance: "same", input: input)
        await fixture.source.waitForGuestReviews(1)
        await gate.open()
        let values = try await (first, second)
        #expect(values.0 == values.1)
        #expect(await fixture.source.count("guestReview") == 1)

        let clock = CheckingTestClock()
        let timeout = GuestWizardGeneration(
            source: fixture.source, secrets: fixture.secrets, deviceIdentity: fixture.device,
            sleep: { seconds in
                #expect(seconds == 30)
                try await clock.clock.sleepUntil(seconds)
            })
        await fixture.source.configure(beforeReview: { try await clock.clock.sleepUntil(100) })
        let request = Task { try await timeout.review(instance: "timeout", input: input) }
        try await eventually { clock.deadlines.contains(30) && clock.deadlines.contains(100) }
        clock.advance(to: 30)
        await #expect(throws: DataFailure.server(status: nil)) { try await request.value }
    }
}

extension GenerationSource {
    func reviewGuestTrip(_ input: ApiGuestTripReviewInput) async throws -> ApiTripReview {
        guestInputs.append(input)
        record("guestReview")
        if let guestHandler { return try await guestHandler(input) }
        try await beforeReview()
        if !reviewResults.isEmpty { return try reviewResults.removeFirst().get() }
        if let reviewFailure { throw reviewFailure }
        return reviewValue
    }
    func handleGuestReview(_ handler: @escaping @Sendable (ApiGuestTripReviewInput) async throws -> ApiTripReview) {
        guestHandler = handler
    }
    func waitForGuestReviews(_ count: Int) async {
        if counts["guestReview", default: 0] >= count { return }
        await withCheckedContinuation { waiters.append(("guestReview", count, $0)) }
    }
}

private struct GuestGenerationFixture {
    let source: GenerationSource
    let secrets = MemoryGuestSecretStore()
    let persistence = GuestDevicePersistence()
    let device: DeviceIdentityStore
    let service: GuestWizardGeneration
    init() throws {
        source = try GenerationSource()
        device = DeviceIdentityStore(persistence: persistence)
        service = GuestWizardGeneration(source: source, secrets: secrets, deviceIdentity: device)
    }
}

private actor GuestDevicePersistence: DeviceIdentityPersistence {
    var value: String?
    var writes = 0
    func readDeviceID() -> String? { value }
    func writeDeviceID(_ value: String) {
        self.value = value
        writes += 1
    }
}

private func guestGenerationInput() throws -> ApiTripReviewInput {
    ApiTripReviewInput(
        input: try generationInput(),
        profile: JSONObject([
            "habitual_bed": .string("23:00"), "habitual_wake": .string("07:00"), "chronotype": .string("intermediate"),
            "age_band": .string("18_64"), "shift_work": .bool(false),
        ]))
}

private func guestReview(token: String, secret: String? = nil) throws -> ApiTripReview {
    var value = try generationReview()
    value.identity.token = token
    value.identity.guestSecret = secret
    return value
}

private actor PausedGuestSecrets: GuestSecretStore {
    let stored = GenerationGate()
    let release = GenerationGate()
    private let memory = MemoryGuestSecretStore()
    func set(_ secret: String, for token: String) async { await memory.set(secret, for: token) }
    func get(for token: String) async -> String? { await memory.get(for: token) }
    func delete(for token: String) async { await memory.delete(for: token) }
    func deleteAll() async { await memory.deleteAll() }
    func rotate(from oldToken: String?, to newToken: String, secret: String) async {
        await memory.rotate(from: oldToken, to: newToken, secret: secret)
        await stored.open()
        await release.wait()
    }
}
