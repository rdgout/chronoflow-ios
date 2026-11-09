import AppCore
import DataAccess

public struct TripGenerationReviewResult: Sendable, Equatable {
    public let input: ApiTripReviewInput
    public let review: ApiTripReview
    public let edit: TripEditContext?
    public init(input: ApiTripReviewInput, review: ApiTripReview, edit: TripEditContext? = nil) {
        self.input = input
        self.review = review
        self.edit = edit
    }
}

extension TripGenerationService {
    private struct ReviewRequest {
        var input: ApiTripReviewInput
        var edit: TripEditContext?
    }

    nonisolated static func performReview(
        source: any DataSource, input: ApiTripReviewInput, edit: TripEditContext?
    ) async throws -> TripGenerationReviewResult {
        var request = try await refreshSource(ReviewRequest(input: input, edit: edit), source: source)
        var review: ApiTripReview
        do {
            review = try await sendReview(request, source: source)
        } catch DataFailure.reviewExpired {
            request = try await refreshSource(request, source: source)
            request.input.identity = nil
            review = try await sendReview(request, source: source)
        }
        if let edit = request.edit, review.identity.sourceRevision != edit.sourceRevision {
            request = try await refreshSource(request, source: source)
            review = try await sendReview(request, source: source)
            guard review.identity.sourceRevision == request.edit?.sourceRevision else {
                throw DataFailure.reviewExpired
            }
        }
        request.input.identity = review.identity
        return TripGenerationReviewResult(input: request.input, review: review, edit: request.edit)
    }

    private nonisolated static func refreshSource(_ original: ReviewRequest, source: any DataSource) async throws
        -> ReviewRequest
    {
        try Task.checkCancellation()
        guard let edit = original.edit else { return original }
        let snapshot = try await source.tripInput(id: edit.tripID)
        try Task.checkCancellation()
        guard snapshot.sourceRevision != edit.sourceRevision else { return original }
        var request = original
        request.input.input = snapshot.input
        request.input.identity = nil
        request.input.profile = nil
        request.edit = TripEditContext(tripID: edit.tripID, sourceRevision: snapshot.sourceRevision)
        return request
    }

    private nonisolated static func sendReview(_ request: ReviewRequest, source: any DataSource) async throws
        -> ApiTripReview
    {
        try Task.checkCancellation()
        if let edit = request.edit {
            return try await source.reviewTripEdit(request.input, id: edit.tripID, sourceRevision: edit.sourceRevision)
        }
        return try await source.reviewTrip(request.input)
    }
}
