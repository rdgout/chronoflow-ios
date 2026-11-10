import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct GuestTripReviewAPITests {
    @Test func firstCallMatchesGuestRequestRules() throws {
        var request = try guestReviewInput()
        request.input.return = request.input.outbound
        request.input.tripEndKind = "return_legs"
        request.input.tripEndNights = 7
        request.input.override = ApiTripInputOverride(use: true, habitualBed: "22:00", habitualWake: "06:00")
        for key in [
            "bipolar", "eye_disease", "eyeDisease", "pregnancy", "vte", "sleep_phase_disorder",
            "oral_contraception", "caffeine_ruled_out", "unrecognised", "invalidDrafts",
        ] { request.profile[key] = .bool(true) }
        let body = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(request))
        let expected = try JSONDecoder().decode(JSONObject.self, from: fixture("wizard/guest-review-request.json"))
        #expect(body == expected)
        #expect(body["return"] == nil && body["override"] == nil)
        #expect(body["profile"]?.object?["habitual_bed"] == .string("23:00"))
        #expect(body["profile"]?.object?["habitual_wake"] == .string("07:00"))
        #expect(body["draft_token"] == .null && body["input_revision"] == .number(0))
        #expect(body["review_revision"] == .null && body["guest_secret"] == nil)
    }

    @Test func subsequentIdentityAndSecretAreFlattened() throws {
        var request = try guestReviewInput()
        request.identity = ApiReviewIdentity(token: "draft", inputRevision: 2, reviewRevision: 3)
        request.guestSecret = String(repeating: "a", count: 64)
        let body = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(request))
        #expect(body["draft_token"] == .string("draft"))
        #expect(body["input_revision"] == .number(2) && body["review_revision"] == .number(3))
        #expect(body["guest_secret"] == .string(String(repeating: "a", count: 64)))
        #expect(body["identity"] == nil && body["source_revision"] == nil)
    }

    @Test(arguments: [true, false])
    func publicRouteDecodesMintedOrNullSecret(minted: Bool) async throws {
        var response = try JSONDecoder().decode(JSONObject.self, from: fixture("wizard/review.json"))
        var identity = response["identity"]!.object!
        identity["guestSecret"] = minted ? .string(String(repeating: "a", count: 64)) : .null
        response["identity"] = .object(identity)
        let text = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
        let expected = try JSONDecoder().decode(JSONObject.self, from: fixture("wizard/guest-review-request.json"))
        let server = StubServer { request in
            #expect(request.httpMethod == "POST" && request.url?.path == "/v1/guest/trips/review")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.timeoutInterval == 90)
            let body = try requestJSON(request)
            #expect(body == expected)
            return .init(200, text)
        }
        let source = APIDataSource(client: try server.client())
        let review = try await source.reviewGuestTrip(guestReviewInput())
        #expect(review.identity.guestSecret == (minted ? String(repeating: "a", count: 64) : nil))
        #expect(server.requests.count == 1)
    }

    @Test(arguments: ["expired", "validation-expired", "throttled", "bare-429", "profile"])
    func mapsGuestFailures(kind: String) async throws {
        let body: String
        let status: Int
        let expected: DataFailure
        switch kind {
        case "expired":
            body = #"{"code":"review_expired","message":"Review expired."}"#
            status = 422
            expected = .reviewExpired
        case "validation-expired":
            body = try fixtureText("wizard/expired.json")
            status = 422
            expected = .reviewExpired
        case "profile":
            body =
                #"{"code":"validation_failed","message":"Invalid.","errors":{"profile.habitual_bed":"Check your bedtime and wake-up time."}}"#
            status = 422
            expected = .profileInvalid(fields: [
                "profile.habitualBed": FieldMessage(key: "Check your bedtime and wake-up time.")
            ])
        default:
            body = kind == "throttled" ? try fixtureText("wizard/throttled.json") : ""
            status = 429
            expected = .throttled(retryAfterSeconds: kind == "throttled" ? 42 : 17, status: 429)
        }
        let server = StubServer { _ in .init(status, body, headers: ["Retry-After": "17"]) }
        let source = APIDataSource(client: try server.client())
        await #expect(throws: expected) { try await source.reviewGuestTrip(guestReviewInput()) }
        #expect(server.requests.count == 1)
    }
}

func guestReviewInput() throws -> ApiGuestTripReviewInput {
    let body = try JSONDecoder().decode(JSONObject.self, from: fixture("wizard/guest-review-request.json"))
    return try ApiGuestTripReviewInput(
        input: wizardInput(), profile: JSONObject(body["profile"]!.object!), deviceID: body["device_id"]!.string!)
}
