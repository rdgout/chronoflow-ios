import AppCore
import DataAccess
import Foundation

public actor GuestWizardGeneration: MemberWizardGeneration {
    private struct ReviewKey: Hashable {
        let instance: String
        let fingerprint: Data
    }
    private struct Flight {
        let id: UUID
        let task: Task<TripGenerationReviewResult, any Error>
    }

    private let source: any DataSource
    private let secrets: any GuestSecretStore
    private let deviceIdentity: DeviceIdentityStore
    private let sleep: APIClient.Sleep
    private var reviews: [ReviewKey: Flight] = [:]
    private var current: [String: ReviewKey] = [:]
    private var cancelled = false

    public init(
        source: any DataSource, secrets: any GuestSecretStore, deviceIdentity: DeviceIdentityStore,
        sleep: @escaping APIClient.Sleep = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.source = source
        self.secrets = secrets
        self.deviceIdentity = deviceIdentity
        self.sleep = sleep
    }

    public func review(instance: String, input: ApiTripReviewInput) async throws -> TripGenerationReviewResult {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        var input = input
        input.profile = ProfilePreferences.request(input.profile ?? JSONObject())
        input.identity?.guestSecret = nil
        input.input.return = nil
        input.input.tripEndKind = "one_way"
        input.input.tripEndNights = nil
        input.input.tripEndCheckOutDate = nil
        input.input.override = ApiTripInputOverride(use: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let key = ReviewKey(instance: instance, fingerprint: try encoder.encode(input))
        let flight: Flight
        if let pending = reviews[key] {
            flight = pending
        } else {
            current[instance] = key
            let id = UUID()
            let task = Task { [input, sleep] in
                try await withThrowingTaskGroup(of: TripGenerationReviewResult.self) { group in
                    group.addTask { try await self.performReview(key: key, id: id, input: input) }
                    group.addTask {
                        try await sleep(30)
                        try Task.checkCancellation()
                        throw DataFailure.server(status: nil)
                    }
                    defer { group.cancelAll() }
                    return try await group.next()!
                }
            }
            flight = Flight(id: id, task: task)
            reviews[key] = flight
        }
        defer {
            if reviews[key]?.id == flight.id { reviews[key] = nil }
        }
        return try await withTaskCancellationHandler {
            let result = try await flight.task.value
            guard !Task.isCancelled, !cancelled, current[instance] == key else {
                try await secrets.delete(for: result.review.identity.token)
                throw CancellationError()
            }
            return result
        } onCancel: {
            Task { await self.cancelReview(key: key, id: flight.id) }
        }
    }

    private func performReview(key: ReviewKey, id: UUID, input: ApiTripReviewInput) async throws
        -> TripGenerationReviewResult
    {
        let oldToken = input.identity?.token
        let secret: String?
        if let oldToken { secret = try await secrets.get(for: oldToken) } else { secret = nil }
        let deviceID = try await deviceIdentity.identity()
        try Task.checkCancellation()
        var request = ApiGuestTripReviewInput(
            input: input.input, identity: input.identity, profile: input.profile ?? JSONObject(),
            deviceID: deviceID, guestSecret: secret)
        var review: ApiTripReview
        do {
            review = try await send(request)
        } catch DataFailure.reviewExpired {
            guard oldToken != nil, isCurrent(key: key, id: id), !Task.isCancelled else {
                throw DataFailure.reviewExpired
            }
            request.identity = nil
            review = try await send(request)
        }
        let token = review.identity.token
        if let nextSecret = review.identity.guestSecret ?? secret {
            try await secrets.rotate(from: oldToken, to: token, secret: nextSecret)
        }
        guard !Task.isCancelled, isCurrent(key: key, id: id) else {
            try await secrets.delete(for: token)
            throw CancellationError()
        }
        review.identity.guestSecret = nil
        var resultInput = input
        resultInput.identity = review.identity
        return TripGenerationReviewResult(input: resultInput, review: review)
    }

    private func send(_ input: ApiGuestTripReviewInput) async throws -> ApiTripReview {
        do { return try await source.reviewGuestTrip(input) } catch let failure as DataFailure {
            throw TripWizardErrors.map(failure, outboundCount: input.input.outbound.legs.count)
        }
    }

    private func isCurrent(key: ReviewKey, id: UUID) -> Bool {
        !cancelled && current[key.instance] == key && reviews[key]?.id == id
    }

    private func cancelReview(key: ReviewKey, id: UUID) {
        guard let flight = reviews[key], flight.id == id else { return }
        flight.task.cancel()
        reviews[key] = nil
    }

    public func cancelReviews(instance: String) {
        for (key, flight) in reviews where key.instance == instance {
            cancelReview(key: key, id: flight.id)
        }
        current[instance] = nil
    }

    public func cancel() {
        cancelled = true
        for flight in reviews.values { flight.task.cancel() }
        reviews.removeAll()
        current.removeAll()
    }
}
