import AppCore
import Foundation
import Testing

@testable import DataAccess

@Suite struct TripWizardAPITests {
    @Test func wireContractsRequestsAndResponses() async throws {
        let input = try wizardInput()
        let response = try fixtureText("wizard/review.json")
        let saved = try fixtureText("wizard/save.json")
        let snapshot = try fixtureText("wizard/snapshot.json")
        let airports = try fixtureText("wizard/airports.json")
        let server = StubServer { request in
            #expect(
                request.value(forHTTPHeaderField: "Authorization")
                    == (request.url!.path == "/v1/airports" ? nil : "Bearer artificial-old-token"))
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            switch (request.httpMethod!, request.url!.path) {
            case ("GET", "/v1/airports"):
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                #expect(query.contains(URLQueryItem(name: "query", value: "São Paulo & city+airport")))
                #expect(query.contains(URLQueryItem(name: "limit", value: "7")))
                return .init(200, airports)
            case ("GET", "/v1/trips/trip/input"): return .init(200, snapshot)
            case ("POST", "/v1/trips/review"), ("POST", "/v1/trips/trip/review"):
                #expect(request.timeoutInterval == 90)
                let body = try requestJSON(request)
                #expect(body["input"] == nil && body["identity"] == nil && body["draftToken"] == nil)
                if case .array(let legs) = body["outbound"]?.object?["legs"] {
                    #expect(legs.first?.object?["from_iata"] == .string("AMS"))
                } else {
                    Issue.record("Missing journey legs")
                }
                #expect(body["draft_token"] == .null && body["input_revision"] == .number(0))
                #expect(body["review_revision"] == .null && body["guest_secret"] == nil)
                var expected = try JSONDecoder().decode(
                    JSONObject.self, from: fixture("wizard/review-request.json"))
                if request.url!.path.contains("trip/review") {
                    expected["source_revision"] = .string(String(repeating: "a", count: 64))
                    expected["profile"] = nil
                }
                #expect(body == expected)
                return .init(200, response)
            case ("POST", "/v1/trips"), ("PUT", "/v1/trips/trip"):
                #expect(request.timeoutInterval == 90)
                let body = try requestJSON(request)
                let expected = try JSONDecoder().decode(JSONObject.self, from: fixture("wizard/save-request.json"))
                #expect(body["draft_token"] == expected["draft_token"])
                #expect(body["input_revision"] == .number(1) && body["review_revision"] == .number(1))
                #expect(
                    Set(body.fields.keys)
                        == (request.httpMethod == "PUT"
                            ? ["draft_token", "input_revision", "review_revision", "source_revision"]
                            : ["draft_token", "input_revision", "review_revision"]))
                return .init(request.httpMethod == "POST" ? 201 : 200, saved)
            default:
                Issue.record("Unexpected wizard endpoint")
                return .init(500)
            }
        }
        let source = APIDataSource(client: try server.client())
        let request = try JSONDecoder().decode(JSONObject.self, from: fixture("wizard/review-request.json"))
        let profile = JSONObject(request["profile"]!.object!)
        let review = try await source.reviewTrip(ApiTripReviewInput(input: input, profile: profile))
        #expect(review.status == .ok && review.canSave && review.summary != nil)
        let identity = try ApiTripSaveInput(identity: review.identity)
        #expect(try await source.saveTrip(identity: identity).tripId == review.identity.token)
        let editInput = try await source.tripInput(id: "trip")
        #expect(editInput.input == input)
        #expect(editInput.input.outbound.legs[0].stay.bedAvailableMode == nil)
        _ = try await source.reviewTripEdit(
            ApiTripReviewInput(input: editInput.input), id: "trip", sourceRevision: editInput.sourceRevision)
        _ = try await source.updateTrip(
            id: "trip", identity: identity, sourceRevision: String(repeating: "a", count: 64))
        #expect(
            try await source.searchAirports(query: "São Paulo & city+airport", limit: 7).first?.timezone
                == "Europe/Amsterdam")
        #expect(server.requests.count == 6)
    }

    @Test func promptsAndFractionalBounds() throws {
        let review = try JSONDecoder().decode(ApiTripReview.self, from: fixture("wizard/needs-answers.json"))
        #expect(review.status == .needsAnswers && review.summary == nil && !review.canSave)
        #expect(review.prompts.map(\.kind) == [.ageBand, .screening])
        #expect(review.prompts[0].answer["age_band"] == .null)
        let shape = try JSONDecoder().decode(
            ApiReviewPromptShape.self, from: Data(#"{"kind":"options","options":["rated"],"min":0.1,"max":9.9}"#.utf8))
        #expect(shape.min == 0.1 && shape.max == 9.9)
    }

    @Test(arguments: ["unknown-field", "journey", "capacity", "profile", "expired", "credits", "throttled"])
    func typedErrors(name: String) async throws {
        let text = try fixtureText("wizard/\(name).json")
        let server = StubServer { _ in .init(name == "throttled" ? 429 : 422, text) }
        let source = APIDataSource(client: try server.client())
        do {
            _ = try await source.reviewTrip(ApiTripReviewInput(input: wizardInput()))
            Issue.record("Expected wizard error")
        } catch let error as DataFailure {
            switch name {
            case "unknown-field":
                #expect(
                    error
                        == .validation(
                            fields: ["legs.0.surprise": FieldMessage(key: "This setting cannot be changed here.")],
                            status: 422))
            case "journey":
                guard case .validation(let fields, _) = error else {
                    Issue.record("Expected fields")
                    return
                }
                #expect(fields["stays.0.bedAvailableFromLocal"] != nil)
                #expect(fields["legs.1.arriveLocal"] != nil && fields["preparation.days"] == nil)
                #expect(fields["end.nights"] != nil)
            case "profile":
                guard case .profileInvalid(let fields) = error else {
                    Issue.record("Expected profileInvalid")
                    return
                }
                #expect(fields["profile"] != nil && fields["profile.habitualBed"] != nil)
            case "capacity": #expect(error == .saveCapacity)
            case "expired": #expect(error == .reviewExpired)
            case "credits": #expect(error == .notEnoughCredits)
            case "throttled": #expect(error == .throttled(retryAfterSeconds: 42, status: 429))
            default: Issue.record("Unexpected fixture")
            }
        }
        #expect(server.requests.count == 1)
    }

    @Test(arguments: ["review", "save", "update"])
    func every429RetainsRetryDeadline(operation: String) async throws {
        let server = StubServer { _ in .init(429, "not json", headers: ["Retry-After": "17"]) }
        let source = APIDataSource(client: try server.client())
        let review = try JSONDecoder().decode(ApiTripReview.self, from: fixture("wizard/review.json"))
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 17, status: 429)) {
            switch operation {
            case "review": _ = try await source.reviewTrip(ApiTripReviewInput(input: wizardInput()))
            case "save": _ = try await source.saveTrip(identity: ApiTripSaveInput(identity: review.identity))
            default:
                _ = try await source.updateTrip(
                    id: "trip", identity: ApiTripSaveInput(identity: review.identity), sourceRevision: "source")
            }
        }
    }

    @Test func bodyRetryHintSurvivesMissingEnvelopeCode() async throws {
        let server = StubServer { _ in .init(429, #"{"retryAfterSeconds":23}"#) }
        let source = APIDataSource(client: try server.client())
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 23, status: 429)) {
            try await source.reviewTrip(ApiTripReviewInput(input: wizardInput()))
        }
    }

    @Test func saveBodyThrottleAndEmailVerification() async throws {
        let review = try JSONDecoder().decode(ApiTripReview.self, from: fixture("wizard/review.json"))
        let text = try fixtureText("wizard/throttled.json")
        let server = StubServer { _ in .init(429, text, headers: ["Retry-After": "99"]) }
        let source = APIDataSource(client: try server.client())
        await #expect(throws: DataFailure.throttled(retryAfterSeconds: 42, status: 429)) {
            try await source.saveTrip(identity: ApiTripSaveInput(identity: review.identity))
        }
        let forbidden = try fixtureText("errors/email_unverified.json")
        let denied = StubServer { _ in .init(403, forbidden) }
        let unverified = APIDataSource(client: try denied.client())
        await #expect(throws: DataFailure.emailUnverified(status: 403)) {
            try await unverified.reviewTrip(ApiTripReviewInput(input: wizardInput()))
        }
    }

    @Test(arguments: ["capacity", "expired", "credits", "profile"])
    func saveMapsDomainValidation(name: String) async throws {
        let body = try fixtureText("wizard/\(name).json")
        let server = StubServer { _ in .init(422, body) }
        let source = APIDataSource(client: try server.client())
        let identity = try ApiTripSaveInput(
            identity: JSONDecoder().decode(ApiTripReview.self, from: fixture("wizard/review.json")).identity)
        do {
            _ = try await source.saveTrip(identity: identity)
            Issue.record("Expected domain validation")
        } catch let failure as DataFailure {
            switch name {
            case "capacity": #expect(failure == .saveCapacity)
            case "expired": #expect(failure == .reviewExpired)
            case "credits": #expect(failure == .notEnoughCredits)
            default:
                guard case .profileInvalid(let fields) = failure else {
                    Issue.record("Expected profileInvalid")
                    return
                }
                #expect(fields["profile.habitual_bed"] != nil)
            }
        }
        #expect(server.requests.count == 1)
    }

    @Test func transportAndDeadlineAreOfflineWithoutRetry() async throws {
        let failed = StubServer { _ in .init(error: URLError(.notConnectedToInternet)) }
        let source = APIDataSource(client: try failed.client())
        await #expect(throws: DataFailure.offline) {
            try await source.reviewTrip(ApiTripReviewInput(input: wizardInput()))
        }
        #expect(failed.requests.count == 1)
        let held = StubServer { _ in .init(hold: true) }
        let client = try held.client(sleep: { seconds in
            #expect(seconds == 90)
            await held.started.wait()
        })
        let timeout = APIDataSource(client: client)
        await #expect(throws: DataFailure.offline) {
            try await timeout.reviewTrip(ApiTripReviewInput(input: wizardInput()))
        }
        #expect(held.requests.count == 1)
    }
}

func wizardInput() throws -> ApiTripInput {
    try JSONDecoder().decode(ApiTripInput.self, from: fixture("wizard/input.json"))
}
