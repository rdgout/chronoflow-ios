import AppCore
import Foundation

extension APIDataSource {
    public func searchAirports(query: String, limit: Int? = nil) async throws -> [ApiAirportSuggestion] {
        var parameters = ["query": query]
        if let limit { parameters["limit"] = String(limit) }
        let result: ApiAirportSearchResults = try await client.request(
            APIEndpoint(path: ["airports"], access: .publicRoute, query: parameters))
        return result.airports
    }

    public func reviewTrip(_ input: ApiTripReviewInput) async throws -> ApiTripReview {
        try await review(input, path: ["trips", "review"])
    }

    public func reviewGuestTrip(_ input: ApiGuestTripReviewInput) async throws -> ApiTripReview {
        do {
            return try await client.request(
                APIEndpoint(
                    method: "POST", path: ["guest", "trips", "review"], access: .publicRoute,
                    body: JSONEncoder().encode(input), timeout: 90))
        } catch let failure as DataFailure {
            throw TripWizardErrors.map(failure, outboundCount: input.input.outbound.legs.count)
        }
    }

    public func reviewTripEdit(_ input: ApiTripReviewInput, id: String, sourceRevision: String) async throws
        -> ApiTripReview
    {
        return try await review(input, path: ["trips", id, "review"], sourceRevision: sourceRevision)
    }

    private func review(_ input: ApiTripReviewInput, path: [String], sourceRevision: String? = nil) async throws
        -> ApiTripReview
    {
        var body = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(input))
        if let sourceRevision { body["source_revision"] = .string(sourceRevision) }
        do {
            return try await client.request(
                APIEndpoint(method: "POST", path: path, body: JSONEncoder().encode(body), timeout: 90))
        } catch let failure as DataFailure {
            throw TripWizardErrors.map(failure, outboundCount: input.input.outbound.legs.count)
        }
    }

    public func saveTrip(identity: ApiTripSaveInput) async throws -> ApiTripSaveResult {
        try await save(identity: identity, path: ["trips"], method: "POST", sourceRevision: nil, expectedStatus: 201)
    }

    public func updateTrip(id: String, identity: ApiTripSaveInput, sourceRevision: String) async throws
        -> ApiTripSaveResult
    {
        try await save(
            identity: identity, path: ["trips", id], method: "PUT", sourceRevision: sourceRevision, expectedStatus: 200)
    }

    private func save(
        identity: ApiTripSaveInput, path: [String], method: String, sourceRevision: String?, expectedStatus: Int
    ) async throws -> ApiTripSaveResult {
        var body = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(identity))
        if let sourceRevision { body["source_revision"] = .string(sourceRevision) }
        do {
            let result: ApiTripSaveResult = try await client.request(
                APIEndpoint(method: method, path: path, body: JSONEncoder().encode(body), timeout: 90),
                expectedStatus: expectedStatus)
            guard !result.tripId.isEmpty else { throw DataFailure.server(status: expectedStatus) }
            return result
        } catch let failure as DataFailure { throw TripWizardErrors.map(failure) }
    }

    public func tripInput(id: String) async throws -> ApiTripInputSnapshot {
        try await client.request(APIEndpoint(path: ["trips", id, "input"]))
    }
}
