import AppCore
import DataAccess
import Foundation

public struct TripGenerationEffects: Sendable {
    public var mergeProfile: @Sendable (JSONObject) async throws -> Void
    public var pullCreatedTrip: @Sendable (String) async throws -> Void
    public var requestSync: @Sendable () async -> Void

    public init(
        mergeProfile: @escaping @Sendable (JSONObject) async throws -> Void,
        pullCreatedTrip: @escaping @Sendable (String) async throws -> Void,
        requestSync: @escaping @Sendable () async -> Void
    ) {
        self.mergeProfile = mergeProfile
        self.pullCreatedTrip = pullCreatedTrip
        self.requestSync = requestSync
    }
}

public struct TripEditContext: Sendable, Equatable, Hashable {
    public let tripID: String
    public let sourceRevision: String
    public init(tripID: String, sourceRevision: String) {
        self.tripID = tripID
        self.sourceRevision = sourceRevision
    }
}

public struct TripGenerationState: Sendable, Equatable {
    public let instance: String
    public var input: ApiTripReviewInput
    public var edit: TripEditContext?
    public var review: ApiTripReview?
    public var savedTripId: String?
    public var identity: ApiReviewIdentity? { review?.identity }

    public init(
        instance: String, input: ApiTripReviewInput, review: ApiTripReview? = nil,
        edit: TripEditContext? = nil, savedTripId: String? = nil
    ) {
        self.instance = instance
        self.input = input
        if let review { self.input.identity = review.identity }
        self.edit = edit
        self.review = review
        self.savedTripId = savedTripId
    }
}

public struct TripGenerationSaveResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case saved(tripId: String)
        case reReviewNeeded(Reason)
        case failed(DataFailure)
    }
    public enum Reason: Sendable, Equatable { case reviewExpired, notEnoughCredits }
    public let state: TripGenerationState
    public let outcome: Outcome
}

public actor TripGenerationService {
    private struct ReviewKey: Hashable {
        let instance: String
        let fingerprint: Data
        let token: String?
        let reviewRevision: Int?
        let edit: TripEditContext?
    }
    private struct SaveKey: Hashable {
        let instance: String
        let identity: ApiTripSaveInput
        let edit: TripEditContext?
    }
    private let source: any DataSource
    private let effects: TripGenerationEffects
    private let sleep: APIClient.Sleep
    private var reviews: [ReviewKey: Task<TripGenerationReviewResult, any Error>] = [:]
    private var reviewIDs: [ReviewKey: UUID] = [:]
    private var saves: [SaveKey: Task<String, any Error>] = [:]
    private var cancelled = false
    private var savedTrips: [SaveKey: String] = [:]

    public init(
        source: any DataSource, effects: TripGenerationEffects,
        sleep: @escaping APIClient.Sleep = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.source = source
        self.effects = effects
        self.sleep = sleep
    }

    public func review(instance: String, input: ApiTripReviewInput, edit: TripEditContext? = nil) async throws
        -> TripGenerationReviewResult
    {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var fingerprintInput = input
        fingerprintInput.identity = nil
        let key = ReviewKey(
            instance: instance, fingerprint: try encoder.encode(fingerprintInput), token: input.identity?.token,
            reviewRevision: input.identity?.reviewRevision, edit: edit)
        if let pending = reviews[key] {
            let value = try await pending.value
            try Task.checkCancellation()
            return value
        }
        let source = source
        let effects = effects
        let sleep = sleep
        let task = Task {
            let result = try await withThrowingTaskGroup(of: TripGenerationReviewResult.self) { group in
                group.addTask {
                    try await Self.performReview(source: source, input: input, edit: edit)
                }
                group.addTask {
                    try await sleep(30)
                    try Task.checkCancellation()
                    throw DataFailure.server(status: nil)
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            try Task.checkCancellation()
            if let profile = result.input.profile, !profile.fields.isEmpty {
                do { try await effects.mergeProfile(profile) } catch {
                    await effects.requestSync()
                    throw error
                }
                await effects.requestSync()
            }
            return result
        }
        let reviewID = UUID()
        reviews[key] = task
        reviewIDs[key] = reviewID
        defer {
            if reviewIDs[key] == reviewID {
                reviews[key] = nil
                reviewIDs[key] = nil
            }
        }
        let result = try await task.value
        try Task.checkCancellation()
        return result
    }

    public func save(_ initial: TripGenerationState) async throws
        -> TripGenerationSaveResult
    {
        try await save(initial, didCreate: { _ in })
    }

    public func save(
        _ initial: TripGenerationState, didCreate: @escaping @Sendable (String) async throws -> Void
    ) async throws -> TripGenerationSaveResult {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        var state = initial
        let edit = state.edit
        do {
            let tripID: String
            if let saved = state.savedTripId {
                tripID = saved
            } else {
                guard let review = state.review, review.canSave else { throw DataFailure.reviewExpired }
                let identity = try ApiTripSaveInput(identity: review.identity)
                let key = SaveKey(instance: state.instance, identity: identity, edit: edit)
                if let saved = savedTrips[key] {
                    tripID = saved
                } else if let pending = saves[key] {
                    tripID = try await pending.value
                } else {
                    let source = source
                    let task = Task {
                        let result: ApiTripSaveResult
                        if let edit {
                            result = try await source.updateTrip(
                                id: edit.tripID, identity: identity, sourceRevision: edit.sourceRevision)
                        } else {
                            result = try await source.saveTrip(identity: identity)
                        }
                        try Task.checkCancellation()
                        return result.tripId
                    }
                    saves[key] = task
                    do {
                        tripID = try await task.value
                        savedTrips[key] = tripID
                        saves[key] = nil
                    } catch {
                        saves[key] = nil
                        throw error
                    }
                }
            }
            state.savedTripId = tripID
            try await didCreate(tripID)
            try? await effects.pullCreatedTrip(tripID)
            await effects.requestSync()
            return TripGenerationSaveResult(state: state, outcome: .saved(tripId: tripID))
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as DataFailure {
            switch failure {
            case .reviewExpired, .notEnoughCredits:
                state.review = nil
                state.input.identity = nil
                state.savedTripId = nil
                return TripGenerationSaveResult(
                    state: state,
                    outcome: .reReviewNeeded(failure == .reviewExpired ? .reviewExpired : .notEnoughCredits))
            default: return TripGenerationSaveResult(state: state, outcome: .failed(failure))
            }
        }
    }

    public func cancelReviews(instance: String) {
        for (key, task) in reviews where key.instance == instance {
            task.cancel()
            reviews[key] = nil
            reviewIDs[key] = nil
        }
    }

    public func cancel() {
        cancelled = true
        for task in reviews.values { task.cancel() }
        for task in saves.values { task.cancel() }
        savedTrips.removeAll()
    }
}
