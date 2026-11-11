import AppCore
import DataAccess
import Foundation
import LocalStore
import Sync
import Testing
import TripWizard

@Suite struct TripGenerationTests {
    @Test func reviewDeduplicatesOnlyMatchingInstanceFingerprintTokenAndRevision() async throws {
        let source = try GenerationSource()
        let gate = GenerationGate()
        await source.configure(beforeReview: { await gate.wait() })
        let effects = EffectProbe()
        let service = TripGenerationService(source: source, effects: await effects.effects())
        var input = ApiTripReviewInput(
            input: try generationInput(), profile: JSONObject(["age_band": .string("18_64")]))
        let original = input
        async let first = service.review(instance: "one", input: original)
        await source.waitForReviews(1)
        async let duplicate = service.review(instance: "one", input: original)
        async let differentInstance = service.review(instance: "two", input: original)
        await source.waitForReviews(2)
        input.input.preparationDays = 2
        let changed = input
        async let differentInput = service.review(instance: "one", input: changed)
        await source.waitForReviews(3)
        input.identity = ApiReviewIdentity(token: "token", inputRevision: 1, reviewRevision: 1)
        let withToken = input
        async let differentToken = service.review(instance: "one", input: withToken)
        await source.waitForReviews(4)
        input.identity?.reviewRevision = 2
        let withRevision = input
        async let differentRevision = service.review(instance: "one", input: withRevision)
        await source.waitForReviews(5)
        await gate.open()
        let values = try await [first, duplicate, differentInstance, differentInput, differentToken, differentRevision]
        #expect(values.count == 6)
        #expect(await source.count("review") == 5)
        #expect(await effects.merges == 5)
        #expect(await effects.syncs == 5)
        _ = try await service.review(instance: "one", input: original)
        #expect(await source.count("review") == 6)
    }

    @Test func reviewDeadlineCancelsRequestAndDoesNotRetry() async throws {
        let source = try GenerationSource()
        await source.configure(beforeReview: { try await Task.sleep(for: .seconds(3600)) })
        let probe = EffectProbe()
        let service = TripGenerationService(
            source: source, effects: await probe.effects(),
            sleep: { seconds in
                #expect(seconds == 30)
                await source.waitForReviews(1)
            })
        await #expect(throws: DataFailure.server(status: nil)) {
            try await service.review(instance: "one", input: ApiTripReviewInput(input: generationInput()))
        }
        #expect(await source.count("review") == 1)
        #expect(await probe.merges == 0)
        #expect(await probe.syncs == 0)
    }

    @Test func saveCachesIdentityAndCallerSavedTripIdSkipsPostEvenWhenPullFails() async throws {
        let source = try GenerationSource()
        let probe = EffectProbe()
        await probe.failPull()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let initial = TripGenerationState(
            instance: "one", input: ApiTripReviewInput(input: try generationInput()), review: try generationReview())
        let first = try await service.save(initial)
        #expect(first.outcome == .saved(tripId: "created") && first.state.savedTripId == "created")
        #expect(try await service.save(initial).outcome == first.outcome)
        #expect(await source.count("save") == 1)
        let recovered = TripGenerationState(
            instance: "recovered", input: ApiTripReviewInput(input: try generationInput()), savedTripId: "already-saved"
        )
        let skipped = try await service.save(recovered)
        #expect(skipped.outcome == .saved(tripId: "already-saved"))
        #expect(await source.count("save") == 1)
        #expect(await probe.pulls == ["created", "created", "already-saved"])
        #expect(await probe.syncs == 3)
    }

    @Test(arguments: [
        DataFailure.reviewExpired, .notEnoughCredits, .throttled(retryAfterSeconds: 31, status: 429), .offline,
        .saveCapacity, .emailUnverified(status: 403),
    ])
    func saveFailuresKeepOrClearIdentityAndNeverRetry(failure: DataFailure) async throws {
        let source = try GenerationSource()
        await source.configure(saveFailure: failure)
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let initial = TripGenerationState(
            instance: "one", input: ApiTripReviewInput(input: try generationInput()), review: try generationReview())
        let result = try await service.save(initial)
        if failure == .reviewExpired || failure == .notEnoughCredits {
            #expect(result.state.identity == nil)
            #expect(result.state.input.identity == nil)
            #expect(result.outcome == .reReviewNeeded(failure == .reviewExpired ? .reviewExpired : .notEnoughCredits))
        } else {
            #expect(result.state.identity == initial.identity && result.outcome == .failed(failure))
        }
        #expect(await source.count("save") == 1)
        #expect(await probe.syncs == 0)
        await source.configure()
        #expect(try await service.save(initial).outcome == .saved(tripId: "created"))
        #expect(await source.count("save") == 2)
    }

    @Test func concurrentSaveUsesOnePostAndEditUsesUpdate() async throws {
        let source = try GenerationSource()
        let gate = GenerationGate()
        await source.configure(beforeSave: { await gate.wait() })
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let state = TripGenerationState(
            instance: "one", input: ApiTripReviewInput(input: try generationInput()), review: try generationReview())
        async let first = service.save(state)
        await source.waitForSaves(1)
        async let second = service.save(state)
        await gate.open()
        let results = try await [first, second]
        #expect(results[0].outcome == results[1].outcome)
        #expect(await source.count("save") == 1)
        let edit = TripEditContext(tripID: "trip", sourceRevision: "revision")
        _ = try await service.review(instance: "edit", input: ApiTripReviewInput(input: generationInput()), edit: edit)
        #expect(await source.lastEdit == edit)
        _ = try await service.save(
            TripGenerationState(
                instance: "edit", input: ApiTripReviewInput(input: generationInput()), review: generationReview(),
                edit: edit))
        #expect(await source.count("update") == 1)
    }

    @Test func failedReviewMakesARequestThenCallerMayRetry() async throws {
        let source = try GenerationSource()
        await source.configure(reviewFailure: .offline)
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        await #expect(throws: DataFailure.offline) {
            try await service.review(instance: "one", input: ApiTripReviewInput(input: generationInput()))
        }
        #expect(await source.count("review") == 1)
        await source.configure()
        _ = try await service.review(instance: "one", input: ApiTripReviewInput(input: generationInput()))
        #expect(await source.count("review") == 2)
    }

    @Test func answeringPromptsPreservesExplicitNulls() async throws {
        let source = try GenerationSource()
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let input = try generationInput()
        var review = try generationReview()
        review.prompts = [
            ApiReviewPrompt(
                id: "busy", kind: .preDepartureBusyHours, blocking: false, required: false,
                text: CopyLine(key: "", args: []), scope: ApiReviewPromptScope(), target: .trip,
                fields: ["pre_departure_busy_answered"], answer: [:],
                shape: ApiReviewPromptShape(kind: .intervals, options: []))
        ]
        let result = try await service.answerPrompts(
            instance: "one", input: ApiTripReviewInput(input: input), review: review,
            answers: ["busy": ["pre_departure_busy_answered": .bool(true)]])
        var expected = try JSONDecoder().decode(
            JSONObject.self,
            from: Data(
                contentsOf: Bundle.module.url(forResource: "input", withExtension: "json", subdirectory: "Fixtures")!))
        expected["pre_departure_busy_answered"] = .bool(true)
        let submitted = try #require(await source.reviewInputs.first)
        for value in [submitted.input, result.input.input] {
            #expect(try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(value)) == expected)
        }
    }

    @Test func answersFollowReturnLegStayAndTopLevelScopes() async throws {
        let source = try GenerationSource()
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        var input = try generationInput()
        input.return = input.outbound
        var review = try generationReview()
        let scope = ApiReviewPromptScope(journey: .return, legIndex: 0, stayIndex: 0)
        review.prompts = [
            ApiReviewPrompt(
                id: "seat", kind: .seatSide, blocking: false, required: false, text: CopyLine(key: "", args: []),
                scope: scope, target: .trip, fields: ["seat_window"], answer: [:],
                shape: ApiReviewPromptShape(kind: .options, options: ["left", "right"])),
            ApiReviewPrompt(
                id: "room", kind: .room, blocking: false, required: false, text: CopyLine(key: "", args: []),
                scope: scope, target: .trip, fields: ["stay.bed_available_mode"], answer: [:],
                shape: ApiReviewPromptShape(kind: .options, options: [])),
            ApiReviewPrompt(
                id: "busy", kind: .preDepartureBusyHours, blocking: false, required: false,
                text: CopyLine(key: "", args: []), scope: ApiReviewPromptScope(), target: .trip,
                fields: ["pre_departure_busy_answered", "pre_departure_busy_intervals"], answer: [:],
                shape: ApiReviewPromptShape(kind: .intervals, options: [])),
        ]
        let result = try await service.answerPrompts(
            instance: "one", input: ApiTripReviewInput(input: input), review: review,
            answers: [
                "seat": ["seat_window": .string("right")], "room": ["stay.bed_available_mode": .string("from_time")],
                "busy": [
                    "pre_departure_busy_answered": .bool(true),
                    "pre_departure_busy_intervals": .array([
                        .object(["start_local": .string("2026-11-09T09:00"), "end_local": .string("2026-11-09T10:00")])
                    ]),
                ],
            ])
        #expect(result.input.input.return?.legs[0].seatWindow == "right")
        #expect(result.input.input.return?.legs[0].stay.bedAvailableMode == "from_time")
        #expect(result.input.input.outbound.legs[0].seatWindow == nil)
        #expect(result.input.input.preDepartureBusyAnswered && result.input.input.preDepartureBusyIntervals.count == 1)
        #expect(result.input.identity == result.review.identity)
    }

    @Test func cancellationStopsInFlightReviewAndEffects() async throws {
        let source = try GenerationSource()
        await source.configure(beforeReview: { try await Task.sleep(for: .seconds(3600)) })
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let request = ApiTripReviewInput(
            input: try generationInput(), profile: JSONObject(["age_band": .string("18_64")]))
        let task = Task { try await service.review(instance: "one", input: request) }
        await source.waitForReviews(1)
        await service.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await probe.merges == 0)
        #expect(await probe.syncs == 0)
    }

    @Test func profileReviewAnswersAndSavedPlanReachSQLite() async throws {
        let now = Date(timeIntervalSince1970: 1_793_750_400)
        let seed = try MockAppSeed.make(now: now)
        let account = try #require(seed.accounts.values.first { $0.twoFactorCode == nil })
        let mock = MockDataSource(seed: seed, now: { now }, sleep: { _ in })
        _ = try await mock.signIn(
            PasswordSignInInput(
                email: account.snapshot.email, password: account.password, deviceID: UUID().uuidString,
                deviceName: "Tests"))
        let source = try GenerationSource(mock: mock)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = AccountDatabase(applicationSupport: directory, namespace: .mock)
        try await database.open(accountID: account.snapshot.id)
        let epoch = SyncEpoch(accountID: try AccountID(account.snapshot.id), generation: 1)
        let snapshot = try await mock.fetchAccount()
        let identity = try await mock.fetchIdentity()
        try await database.write(epoch: epoch) { db in
            try StoreApplication.identity(identity, accountID: epoch.accountID, db: db)
            try StoreApplication.snapshot(snapshot, accountID: epoch.accountID, db: db)
        }
        let sync = EffectProbe()
        let effects = TripGenerationEffects.storing(
            database: database, source: source, epoch: epoch, requestSync: { await sync.synced() }, now: { now })
        let service = TripGenerationService(source: source, effects: effects)
        var input = ApiTripReviewInput(
            input: try generationInput(), profile: JSONObject(["age_band": .null, "shift_work": .null]))
        let first = try await service.review(instance: "one", input: input).review
        #expect(first.status == .needsAnswers)
        let age = try #require(first.prompts.first { $0.kind == .ageBand })
        let screening = try #require(first.prompts.first { $0.fields == ["shift_work"] })
        let answered = try await service.answerPrompts(
            instance: "one", input: input, review: first,
            answers: [age.id: ["age_band": .string("18_64")], screening.id: ["shift_work": .bool(false)]])
        #expect(answered.review.identity.inputRevision == first.identity.inputRevision + 1)
        let body = try #require(
            try await SettingsRepository(database: database).settings().first { $0.section == "bodyClock" })
        #expect(try body.value.decode(JSONObject.self)["ageBand"] == .string("18_64"))
        #expect(await sync.syncs == 2)
        input = answered.input
        input.profile = JSONObject(["habitual_bed": .string("22:00")])
        let reviewed = try await service.review(instance: "one", input: input)
        #expect(reviewed.review.canSave)
        let result = try await service.save(
            TripGenerationState(instance: "one", input: reviewed.input, review: reviewed.review, edit: reviewed.edit))
        let tripID = try #require(result.state.savedTripId)
        let repository = TripRepository(database: database)
        let trip = try #require(try await repository.trips().first { $0.id == tripID })
        let hash = try #require(trip.currentInputHash)
        #expect(try await repository.plan(tripID: tripID, inputHash: hash) != nil)
        #expect(await source.count("save") == 1)
        #expect(await source.count("trips") == 1)
        #expect(await source.count("detail") == 1)
        _ = try await service.save(result.state)
        #expect(await source.count("save") == 1)
        _ = try await OutboxRepository(database: database).enqueue(
            .settings(section: .bodyClock, patch: JSONObject(["habitual_bed": .string("22:30")])))
        try await effects.mergeProfile(JSONObject(["habitual_bed": .string("21:00"), "age_band": .string("65_plus")]))
        let pendingBody = try #require(
            try await SettingsRepository(database: database).settings().first { $0.section == "bodyClock" })
        #expect(try pendingBody.value.decode(JSONObject.self)["habitualBed"] == .string("22:30"))
        #expect(try pendingBody.value.decode(JSONObject.self)["ageBand"] == .string("65_plus"))
        epoch.invalidate()
        await #expect(throws: CancellationError.self) {
            try await effects.mergeProfile(JSONObject(["age_band": .string("65_plus")]))
        }
        try await database.close()
        try FileManager.default.removeItem(at: directory)
    }
}

func generationInput() throws -> ApiTripInput {
    try JSONDecoder().decode(
        ApiTripInput.self,
        from: Data(
            contentsOf: Bundle.module.url(forResource: "input", withExtension: "json", subdirectory: "Fixtures")!))
}
func generationReview() throws -> ApiTripReview {
    try JSONDecoder().decode(
        ApiTripReview.self,
        from: Data(
            contentsOf: Bundle.module.url(forResource: "review", withExtension: "json", subdirectory: "Fixtures")!))
}

actor GenerationGate {
    private var opened = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func open() {
        opened = true
        for continuation in continuations { continuation.resume() }
        continuations.removeAll()
    }
}

actor EffectProbe {
    var merges = 0
    var syncs = 0
    var pulls: [String] = []
    var pullFailure = false
    func failPull() { pullFailure = true }
    func merged() { merges += 1 }
    func synced() { syncs += 1 }
    func pulled(_ id: String) throws {
        pulls.append(id)
        if pullFailure { throw DataFailure.offline }
    }
    func effects() -> TripGenerationEffects {
        TripGenerationEffects(
            mergeProfile: { _ in await self.merged() }, pullCreatedTrip: { try await self.pulled($0) },
            requestSync: { await self.synced() })
    }
}
