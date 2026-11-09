import AppCore
import Foundation
import Observation
import Sync

public struct RefreshFeedback: Sendable, Equatable {
    public let key: String
    public let count: Int?

    public static func outcome(_ result: SyncResult, userInitiated: Bool) -> [Self] {
        guard userInitiated else { return [] }
        switch result.state {
        case .offline: return [Self(key: "Needs a connection", count: nil)]
        case .failed, .unauthorized, .verificationRequired:
            return [Self(key: "Something went wrong", count: nil)]
        case .idle:
            guard result.retryAfter == nil, result.pendingCount == 0, result.refusals.isEmpty else {
                return [Self(key: "Something went wrong", count: nil)]
            }
            let changes = result.changes
            let rows: [(String, Int)] = [
                ("%lld trips added", changes.tripsAdded),
                ("%lld trips updated", changes.tripsUpdated),
                ("%lld trips removed", changes.tripsRemoved),
            ]
            let feedback = rows.filter { $0.1 > 0 }.map { Self(key: $0.0, count: $0.1) }
            return feedback.isEmpty ? [Self(key: "Up to date", count: nil)] : feedback
        }
    }

    public func text(language: Language) -> String { PlanStrings.text(key, language: language, count: count) }
}

@MainActor @Observable public final class RefreshFeedbackModel {
    public private(set) var refreshing = false
    public private(set) var feedback: [RefreshFeedback] = []
    public private(set) var presentationID = UUID()
    public init() {}

    public func refresh(
        userInitiated: Bool = true, action: () async throws -> SyncResult?
    ) async {
        guard !refreshing else { return }
        refreshing = true
        feedback = []
        defer {
            refreshing = false
            presentationID = UUID()
        }
        do {
            let result = try await action()
            try Task.checkCancellation()
            if let result { feedback = RefreshFeedback.outcome(result, userInitiated: userInitiated) }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let state: SyncState = (error as? DataFailure) == .offline ? .offline : .failed
            feedback = RefreshFeedback.outcome(
                SyncResult(state: state, pendingCount: 0), userInitiated: userInitiated)
        }
    }

    public func dismiss() { feedback = [] }
}
