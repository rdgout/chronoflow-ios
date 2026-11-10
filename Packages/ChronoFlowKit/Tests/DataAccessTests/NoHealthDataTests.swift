import AppCore
import Foundation
import Testing

@testable import DataAccess

struct NoHealthDataTests {
    private let retired = ["bipolar", "eye_disease", "pregnancy", "vte", "sleep_phase_disorder", "oral_contraception"]

    @Test func legacyAccountDecodingDiscardsHealthAnswersAndReadinessTargets() throws {
        let url = try #require(
            Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "account"))
        var raw = try JSONDecoder().decode(JSONObject.self, from: Data(contentsOf: url))
        var settings = raw["settings"]!.object!
        var body = settings["bodyClock"]!.object!
        for key in retired { body[ProfilePreferences.camel(key)] = .bool(true) }
        body["excludeCaffeine"] = nil
        body["flightMovementBreaks"] = nil
        body["invalidDrafts"] = .object(["pregnancy": .bool(false), "shift_work": .null])
        settings["bodyClock"] = .object(body)
        raw["settings"] = .object(settings)
        raw["readiness"] = .object([
            "variant": .string("health-adjusted"), "lightDevicesAllowed": .bool(false),
            "missing": .array(retired.map { .object(["question": .string($0)]) }),
            "adjustments": .array([.object(["key": .string("old health copy"), "args": .array([])])]),
        ])
        let value = try JSONDecoder().decode(AccountSnapshot.self, from: JSONEncoder().encode(raw))
        for key in retired { #expect(value.settings.bodyClock[ProfilePreferences.camel(key)] == nil) }
        #expect(value.settings.bodyClock["invalidDrafts"]?.object == ["shift_work": .null])
        #expect(value.settings.bodyClock["excludeCaffeine"] == .bool(false))
        #expect(value.settings.bodyClock["flightMovementBreaks"] == .bool(false))
        #expect(value.readiness["lightDevicesAllowed"] == nil)
        #expect(value.readiness["variant"] == .string("needs-answers"))
        #expect(
            value.readiness["missing"]
                == .array([.object(["question": .null]), .object(["question": .string("shift_work")])]))
        #expect(value.readiness["adjustments"] == .array([]))
        let encoded = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(value))
        #expect(encoded["settings"]?.object?["bodyClock"] == .object(value.settings.bodyClock.fields))
    }

    @Test func preferencesDefaultFalseAndOnlyExplicitMovementPreferenceCarriesOver() {
        let defaults = ProfilePreferences.bodyClock(JSONObject(["vte": .bool(true)]))
        #expect(defaults["flightMovementBreaks"] == .bool(false))
        #expect(defaults["excludeCaffeine"] == .bool(false))
        let legacy = ProfilePreferences.bodyClock(JSONObject(["caffeineRuledOut": .bool(true)]))
        #expect(legacy["excludeCaffeine"] == .bool(true) && legacy["caffeineRuledOut"] == nil)
        let current = ProfilePreferences.bodyClock(
            JSONObject([
                "excludeCaffeine": .bool(false), "caffeineRuledOut": .bool(true), "flightMovementBreaks": .bool(true),
            ]))
        #expect(current["excludeCaffeine"] == .bool(false) && current["flightMovementBreaks"] == .bool(true))
    }

    @Test func patchAllowsOnlyNeutralPreferencesAndRequiresBooleans() throws {
        try SettingsPatchValidation.validate(
            section: .bodyClock,
            patch: JSONObject([
                "exclude_caffeine": .bool(true), "flight_movement_breaks": .bool(false),
            ]))
        for key in retired + ["caffeine_ruled_out"] {
            #expect(throws: DataFailure.self) {
                try SettingsPatchValidation.validate(section: .bodyClock, patch: JSONObject([key: .bool(false)]))
            }
        }
        for key in ["exclude_caffeine", "flight_movement_breaks"] {
            #expect(throws: DataFailure.self) {
                try SettingsPatchValidation.validate(section: .bodyClock, patch: JSONObject([key: .null]))
            }
        }
    }

    @Test func patchEncodingSendsOnlyNeutralPreferencesAndRejectsHealthFieldsBeforeTransport() async throws {
        let account = try fixtureText("account/snapshot.json")
        let server = StubServer { request in
            #expect(request.httpMethod == "PATCH" && request.url?.path == "/v1/account/body-clock")
            let body = try requestJSON(request)
            #expect(
                body
                    == JSONObject([
                        "exclude_caffeine": .bool(true), "flight_movement_breaks": .bool(false),
                    ]))
            return .init(200, account)
        }
        let source = APIDataSource(client: try server.client())
        _ = try await source.send(
            .settings(
                section: .bodyClock,
                patch: JSONObject([
                    "exclude_caffeine": .bool(true), "flight_movement_breaks": .bool(false),
                ])))
        for key in retired {
            await #expect(throws: DataFailure.self) {
                try await source.send(.settings(section: .bodyClock, patch: JSONObject([key: .bool(false)])))
            }
        }
        #expect(server.requests.count == 1)
    }

    @Test func reviewEncodingDropsRetiredFieldsEvenAfterMutation() throws {
        var profile = JSONObject(Dictionary(uniqueKeysWithValues: retired.map { ($0, JSONValue.bool(false)) }))
        profile["exclude_caffeine"] = .bool(true)
        profile["flight_movement_breaks"] = .bool(false)
        profile["shift_work"] = .bool(false)
        var request = ApiTripReviewInput(input: try wizardInput())
        request.profile = profile
        let encoded = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(request))
        #expect(
            encoded["profile"]?.object == [
                "exclude_caffeine": .bool(true), "flight_movement_breaks": .bool(false), "shift_work": .bool(false),
            ])
    }

    @Test func legacyReviewDecodingDiscardsRetiredPrompts() throws {
        var raw = try JSONDecoder().decode(JSONObject.self, from: fixture("wizard/needs-answers.json"))
        guard case .array(var prompts) = raw["prompts"] else { throw DataFailure.server(status: nil) }
        var shift = prompts[1].object!
        shift["answer"] = .object(["shift_work": .bool(false), "pregnancy": .bool(false)])
        prompts[1] = .object(shift)
        for key in retired + ["caffeine_ruled_out"] {
            var prompt = shift
            prompt["id"] = .string("screening:" + key)
            prompt["fields"] = .array([.string(key)])
            prompt["answer"] = .object([key: .bool(false)])
            prompts.append(.object(prompt))
        }
        raw["prompts"] = .array(prompts)
        let review = try JSONDecoder().decode(ApiTripReview.self, from: JSONEncoder().encode(raw))
        #expect(review.prompts.map(\.fields) == [["age_band"], ["shift_work"]])
        #expect(review.prompts[1].answer == ["shift_work": .bool(false)])
        let encoded = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(review))
        if case .array(let values) = encoded["prompts"] { #expect(values.count == 2) }
    }

    @Test func mockRejectsEveryRetiredReviewProfileKeyWith422() async throws {
        let source = try wizardMockSource()
        _ = try await login(source)
        for key in retired + ["caffeine_ruled_out"] {
            do {
                _ = try await source.reviewTrip(
                    ApiTripReviewInput(input: wizardInput(), profile: JSONObject([key: .bool(false)])))
                Issue.record("Accepted retired profile key: \(key)")
            } catch let failure as DataFailure {
                #expect(failure.status == 422)
                #expect(
                    failure
                        == .profileInvalid(fields: [
                            "profile.form": FieldMessage(key: "This setting cannot be changed here.")
                        ]))
            }
        }
    }

    @Test func tripCacheDropsRetiredValuesAndPromptsWhilePreservingUnknownPlanFields() throws {
        var raw = try JSONDecoder().decode(JSONObject.self, from: fixture("trips/detail.json"))
        var plan = raw["plan"]!.object!
        plan["futureField"] = .object(["keep": .string("value"), "pregnancy": .bool(false)])
        plan["prompts"] = .array([
            .object([
                "kind": .string("screening"), "question": .string("bipolar"),
                "text": .object(["key": .string("retired"), "args": .array([])]), "required": .bool(true),
            ])
        ])
        raw["plan"] = .object(plan)
        let response = try TripDetailResponse(data: JSONEncoder().encode(raw))
        let cached = try JSONDecoder().decode(JSONObject.self, from: response.data)
        #expect(cached["plan"]?.object?["futureField"] == .object(["keep": .string("value")]))
        #expect(cached["plan"]?.object?["prompts"] == .array([]))
        #expect(response.detail.plan.prompts.isEmpty)
        let clean = try fixture("trips/detail.json")
        #expect(try TripDetailResponse(data: clean).data == clean)
    }

    @Test func readinessOnlyAgeAndShiftWorkBlockAndPreferencesAdjust() {
        let body = JSONObject(["ageBand": .string("18_64"), "shiftWork": .bool(false)])
        #expect(MockSettings.readiness(body)["variant"] == .string("ready"))
        for key in ["excludeCaffeine", "flightMovementBreaks"] {
            var adjusted = body
            adjusted[key] = .bool(true)
            let ready = MockSettings.readiness(adjusted)
            #expect(ready["variant"] == .string("adjusted") && ready["missing"] == .array([]))
            #expect(ready["lightDevicesAllowed"] == nil)
        }
        var senior = body
        senior["ageBand"] = .string("65_plus")
        #expect(MockSettings.readiness(senior)["variant"] == .string("adjusted"))
        for (key, answer) in [("ageBand", JSONValue.string("under_18")), ("shiftWork", .bool(true))] {
            var excluded = body
            excluded[key] = answer
            #expect(MockSettings.readiness(excluded)["variant"] == .string("excluded"))
        }
    }
}
