import AppCore
import DataAccess
import Foundation
import Testing
import TripWizard

@Suite struct TripGenerationRecoveryTests {
    @Test func expiredReviewRetriesOnceWithoutIdentity() async throws {
        let source = try GenerationSource()
        let fresh = try generationReview()
        await source.queueReviews([.failure(.reviewExpired), .success(fresh)])
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let input = ApiTripReviewInput(
            input: try generationInput(), identity: expiredIdentity(),
            profile: JSONObject(["age_band": .string("18_64")]))
        let result = try await service.review(instance: "one", input: input)
        let requests = await source.reviewInputs
        #expect(requests.map(\.identity) == [input.identity, nil])
        #expect(requests.allSatisfy { $0.input == input.input && $0.profile == input.profile })
        #expect(result.review == fresh && result.input.identity == fresh.identity)
        #expect(await probe.merges == 1)
        #expect(await probe.syncs == 1)
    }

    @Test func secondExpirySurfacesTypedWithoutAnotherRetry() async throws {
        let source = try GenerationSource()
        await source.queueReviews([.failure(.reviewExpired), .failure(.reviewExpired)])
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        await #expect(throws: DataFailure.reviewExpired) {
            try await service.review(
                instance: "one", input: ApiTripReviewInput(input: generationInput(), identity: expiredIdentity()))
        }
        #expect(await source.reviewInputs.map(\.identity) == [expiredIdentity(), nil])
        #expect(await probe.merges == 0)
        #expect(await probe.syncs == 0)
    }

    @Test func editExpiryRefreshesSourceAndReturnsUpdatedDraftForSave() async throws {
        let source = try GenerationSource()
        var updatedInput = try generationInput()
        updatedInput.preparationDays = 1
        await source.queueSnapshots([
            ApiTripInputSnapshot(input: try generationInput(), sourceRevision: "old", airports: [:]),
            ApiTripInputSnapshot(input: updatedInput, sourceRevision: "new", airports: [:]),
        ])
        var fresh = try generationReview()
        fresh.identity.sourceRevision = "new"
        await source.queueReviews([.failure(.reviewExpired), .success(fresh)])
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        var input = ApiTripReviewInput(
            input: try generationInput(), identity: expiredIdentity(),
            profile: JSONObject(["age_band": .string("18_64")]))
        input.input.preparationDays = 2
        let result = try await service.review(
            instance: "one", input: input, edit: TripEditContext(tripID: "trip", sourceRevision: "old"))
        #expect(await source.operations == ["input", "review", "input", "review"])
        #expect(await source.editRequests.map(\.sourceRevision) == ["old", "new"])
        let requests = await source.reviewInputs
        #expect(requests[0] == input)
        #expect(requests[1].identity == nil && requests[1].input == updatedInput)
        #expect(requests[1].profile == nil && result.input.profile == nil)
        #expect(result.input.input == updatedInput && result.input.identity == fresh.identity)
        #expect(result.edit == TripEditContext(tripID: "trip", sourceRevision: "new"))
        let saved = try await service.save(
            TripGenerationState(instance: "one", input: result.input, review: result.review, edit: result.edit))
        #expect(saved.outcome == .saved(tripId: "trip"))
        #expect(await source.lastEdit == result.edit)
    }

    @Test func editRefreshesChangedSourceBeforeFirstReview() async throws {
        let source = try GenerationSource()
        var updatedInput = try generationInput()
        updatedInput.preparationDays = 1
        await source.queueSnapshots([
            ApiTripInputSnapshot(input: updatedInput, sourceRevision: "new", airports: [:])
        ])
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let result = try await service.review(
            instance: "one", input: ApiTripReviewInput(input: generationInput(), identity: expiredIdentity()),
            edit: TripEditContext(tripID: "trip", sourceRevision: "old"))
        let submitted = try #require(await source.reviewInputs.first)
        #expect(submitted.input == updatedInput && submitted.identity == nil)
        #expect(result.edit?.sourceRevision == "new")
        #expect(await source.operations == ["input", "review"])
    }

    @Test(arguments: [false, true])
    func editRevisionMismatchReviewsAgainAndRejectsRepeatedMismatch(repeatedMismatch: Bool) async throws {
        let source = try GenerationSource()
        var updatedInput = try generationInput()
        updatedInput.preparationDays = 1
        await source.queueSnapshots([
            ApiTripInputSnapshot(input: try generationInput(), sourceRevision: "old", airports: [:]),
            ApiTripInputSnapshot(input: updatedInput, sourceRevision: "new", airports: [:]),
        ])
        var mismatched = try generationReview()
        mismatched.identity.sourceRevision = "other"
        var fresh = try generationReview()
        fresh.identity.sourceRevision = repeatedMismatch ? "other" : "new"
        await source.queueReviews([.success(mismatched), .success(fresh)])
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let input = ApiTripReviewInput(input: try generationInput(), identity: expiredIdentity())
        let edit = TripEditContext(tripID: "trip", sourceRevision: "old")
        if repeatedMismatch {
            await #expect(throws: DataFailure.reviewExpired) {
                try await service.review(instance: "one", input: input, edit: edit)
            }
        } else {
            let result = try await service.review(instance: "one", input: input, edit: edit)
            #expect(result.review == fresh && result.input.input == updatedInput)
            #expect(result.edit?.sourceRevision == "new")
        }
        #expect(await source.operations == ["input", "review", "input", "review"])
        #expect(await source.reviewInputs.map(\.identity) == [input.identity, nil])
        #expect(await source.editRequests.map(\.sourceRevision) == ["old", "new"])
    }

    @Test func answeringPromptsAfterExpiryReturnsFreshIdentity() async throws {
        let source = try GenerationSource()
        let fresh = try generationReview()
        await source.queueReviews([.failure(.reviewExpired), .success(fresh), .success(fresh)])
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        var stale = fresh
        stale.identity = expiredIdentity()
        stale.prompts = [
            ApiReviewPrompt(
                id: "age", kind: .ageBand, blocking: true, required: true,
                text: CopyLine(key: "", args: []), scope: ApiReviewPromptScope(), target: .profile,
                fields: ["age_band"], answer: [:], shape: ApiReviewPromptShape(kind: .options, options: ["18_64"]))
        ]
        let result = try await service.answerPrompts(
            instance: "one", input: ApiTripReviewInput(input: generationInput()), review: stale,
            answers: ["age": ["age_band": .string("18_64")]])
        #expect(result.input.identity == fresh.identity)
        #expect(result.input.profile?["age_band"] == .string("18_64"))
        _ = try await service.review(instance: "one", input: result.input)
        let requests = await source.reviewInputs
        #expect(requests.map(\.identity) == [stale.identity, nil, fresh.identity])
        #expect(requests.allSatisfy { $0.profile == result.input.profile })
    }

    @Test(arguments: [DataFailure.reviewExpired, .notEnoughCredits])
    func saveRecoveryInputReviewsWithoutDeadIdentity(failure: DataFailure) async throws {
        let source = try GenerationSource()
        await source.configure(saveFailure: failure)
        let probe = EffectProbe()
        let service = TripGenerationService(source: source, effects: await probe.effects())
        let input = ApiTripReviewInput(
            input: try generationInput(), profile: JSONObject(["age_band": .string("18_64")]))
        let saved = try await service.save(
            TripGenerationState(instance: "one", input: input, review: generationReview()))
        #expect(saved.outcome == .reReviewNeeded(failure == .reviewExpired ? .reviewExpired : .notEnoughCredits))
        #expect(saved.state.review == nil && saved.state.input.identity == nil)
        #expect(saved.state.input.input == input.input && saved.state.input.profile == input.profile)
        _ = try await service.review(instance: saved.state.instance, input: saved.state.input, edit: saved.state.edit)
        #expect(await source.reviewInputs.map(\.identity) == [nil])
        #expect(await source.count("save") == 1)
    }
}

private func expiredIdentity() -> ApiReviewIdentity {
    ApiReviewIdentity(token: "expired", inputRevision: 1, reviewRevision: 1)
}
