import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct MockTripGenerationTests {
    @Test(arguments: [false, true])
    func unknownAirportIsAFieldErrorBeforePlanGeneration(destination: Bool) async throws {
        let source = try wizardMockSource()
        _ = try await login(source)
        var input = try wizardInput()
        if destination {
            input.outbound.legs[0].toIata = "NRT"
        } else {
            input.outbound.legs[0].fromIata = "NRT"
        }
        let field = destination ? "legs.0.toIata" : "legs.0.fromIata"
        await #expect(
            throws: DataFailure.validation(
                fields: [field: FieldMessage(key: "Choose an airport from the search results.")], status: 422)
        ) {
            try await source.reviewTrip(ApiTripReviewInput(input: input))
        }
    }

    @Test func routeChoiceCreditsAndIdempotentReceiptSurviveRestoration() async throws {
        let store = MemoryMockStateStore()
        let source = try wizardMockSource(store: store)
        _ = try await login(source)
        let before = try await source.fetchTrips().count
        let input = try wizardInput()
        let review = try await source.reviewTrip(ApiTripReviewInput(input: input, profile: wizardProfile()))
        #expect(review.canSave && review.price.cost == 1 && review.summary != nil)
        #expect(review.itinerary.legs.first?.flightMin == 660)
        let identity = try ApiTripSaveInput(identity: review.identity)
        let saved = try await source.saveTrip(identity: identity)
        #expect(try await source.saveTrip(identity: identity) == saved)
        #expect(try await source.fetchTrips().count == before + 1)
        let detail = try await source.fetchTripDetail(id: saved.tripId)
        #expect(detail.trip.to.iata == "HND" && !detail.plan.blocks.isEmpty)
        #expect(
            detail.plan.blocks.contains {
                if case .flight(let params) = $0.params { params.toIata == "HND" } else { false }
            })
        #expect(try await source.tripInput(id: saved.tripId).input == input)
        let balance = try await source.fetchAccount().settings.planCredits
        let restored = try wizardMockSource(store: store)
        _ = try await login(restored)
        #expect(try await restored.saveTrip(identity: identity) == saved)
        #expect(try await restored.fetchAccount().settings.planCredits == balance)
        var west = input
        west.outbound.legs[0].toIata = "JFK"
        west.outbound.legs[0].arriveLocal = "2026-11-10T14:00"
        let westReview = try await source.reviewTrip(ApiTripReviewInput(input: west, profile: wizardProfile()))
        #expect(westReview.summary?.adaptation.direction == .later)
    }

    @Test func missingAnswersAgeAndScreeningExclusion() async throws {
        let source = try wizardMockSource()
        _ = try await login(source)
        let missing = JSONObject([
            "age_band": .null, "shift_work": .null,
        ])
        let first = try await source.reviewTrip(ApiTripReviewInput(input: wizardInput(), profile: missing))
        #expect(first.status == .needsAnswers && first.prompts.count == 2 && !first.canSave)
        #expect(first.prompts.first?.kind == .ageBand && first.prompts[1].kind == .screening)
        let answered = try await source.reviewTrip(
            ApiTripReviewInput(input: wizardInput(), identity: first.identity, profile: wizardProfile()))
        #expect(answered.identity.token == first.identity.token && answered.identity.inputRevision == 2)
        #expect(answered.status == .ok && answered.canSave)
        let excluded = try await source.reviewTrip(
            ApiTripReviewInput(input: wizardInput(), profile: JSONObject(["shift_work": .bool(true)])))
        #expect(excluded.status == .noPlan && excluded.prompts.isEmpty && excluded.summary == nil)
        let underage = try await source.reviewTrip(
            ApiTripReviewInput(input: wizardInput(), profile: JSONObject(["age_band": .string("under_18")])))
        #expect(underage.status == .noPlan && !underage.canSave)
        await #expect(throws: DataFailure.reviewExpired) {
            try await source.saveTrip(identity: ApiTripSaveInput(identity: underage.identity))
        }
    }

    @Test func editSnapshotAndRevisionAndAirportSearch() async throws {
        let source = try wizardMockSource()
        _ = try await login(source)
        #expect(try await source.searchAirports(query: "Schiphol").first?.iata == "AMS")
        #expect(try await source.searchAirports(query: "zz").isEmpty)
        let review = try await source.reviewTrip(ApiTripReviewInput(input: wizardInput(), profile: wizardProfile()))
        let saved = try await source.saveTrip(identity: ApiTripSaveInput(identity: review.identity))
        let snapshot = try await source.tripInput(id: saved.tripId)
        var input = snapshot.input
        input.preparationDays = 1
        await #expect(throws: DataFailure.reviewExpired) {
            try await source.reviewTripEdit(ApiTripReviewInput(input: input), id: saved.tripId, sourceRevision: "stale")
        }
        let edit = try await source.reviewTripEdit(
            ApiTripReviewInput(input: input), id: saved.tripId, sourceRevision: snapshot.sourceRevision)
        #expect(edit.price.cost == 0 && edit.canSave)
        let identity = try ApiTripSaveInput(identity: edit.identity)
        #expect(
            try await source.updateTrip(id: saved.tripId, identity: identity, sourceRevision: snapshot.sourceRevision)
                == saved)
        #expect(
            try await source.updateTrip(id: saved.tripId, identity: identity, sourceRevision: snapshot.sourceRevision)
                == saved)
        #expect(try await source.tripInput(id: saved.tripId).input.preparationDays == 1)
        #expect(try await source.tripInput(id: saved.tripId).sourceRevision != snapshot.sourceRevision)
    }

    @Test func seededTripInputsAndExpiredDrafts() async throws {
        let clock = MockClock()
        let source = try mockSource(clock: clock, seed: MockAppSeed.make(now: clock.now()))
        _ = try await login(source)
        let trip = try #require(try await source.fetchTrips().first)
        let snapshot = try await source.tripInput(id: trip.card.id)
        #expect(!snapshot.input.outbound.legs.isEmpty && !snapshot.airports.isEmpty)
        _ = try await source.reviewTripEdit(
            ApiTripReviewInput(input: snapshot.input), id: trip.card.id, sourceRevision: snapshot.sourceRevision)
        let review = try await source.reviewTrip(ApiTripReviewInput(input: wizardInput(), profile: wizardProfile()))
        clock.advance(1801)
        await #expect(throws: DataFailure.reviewExpired) {
            try await source.saveTrip(identity: ApiTripSaveInput(identity: review.identity))
        }
    }

    @Test func profileFailureAndOfflineAreRequestFailures() async throws {
        let source = try wizardMockSource()
        _ = try await login(source)
        do {
            _ = try await source.reviewTrip(
                ApiTripReviewInput(input: wizardInput(), profile: JSONObject(["age_band": .string("invalid")])))
            Issue.record("Expected profile validation")
        } catch let failure as DataFailure {
            guard case .profileInvalid = failure else {
                Issue.record("Expected profileInvalid")
                return
            }
        }
        await source.setOffline(true)
        await #expect(throws: DataFailure.offline) {
            try await source.reviewTrip(ApiTripReviewInput(input: wizardInput()))
        }
    }
}

func wizardProfile() -> JSONObject {
    JSONObject([
        "age_band": .string("18_64"), "shift_work": .bool(false),
        "exclude_caffeine": .bool(false), "flight_movement_breaks": .bool(false),
    ])
}

func wizardMockSource(store: any MockStateStore = MemoryMockStateStore()) throws -> MockDataSource {
    var seed = try scenarioState()
    seed.accounts[demoID]!.snapshot.settings.planCredits = JSONObject([
        "credits": .number(3), "unlimited": .bool(false),
    ])
    return try mockSource(store: store, seed: seed)
}
