import AppCore
import Foundation
import Sync
import Testing

@testable import PlanUI

@Suite @MainActor struct RefreshFeedbackTests {
    @Test(arguments: [
        (SyncState.idle, "Up to date", "Alles is bijgewerkt"),
        (.offline, "Needs a connection", "Verbinding nodig"),
        (.failed, "Something went wrong", "Er ging iets mis"),
        (.unauthorized, "Something went wrong", "Er ging iets mis"),
        (.verificationRequired, "Something went wrong", "Er ging iets mis"),
    ])
    func statesUseExistingCopy(state: SyncState, english: String, dutch: String) {
        let feedback = RefreshFeedback.outcome(SyncResult(state: state, pendingCount: 0), userInitiated: true)
        #expect(feedback.map { $0.text(language: .en) } == [english])
        #expect(feedback.map { $0.text(language: .nl) } == [dutch])
    }

    @Test(arguments: [1, 3])
    func addedUpdatedRemovedUseCatalogPlurals(count: Int) {
        let result = SyncResult(
            state: .idle, pendingCount: 0,
            changes: SyncChanges(
                tripsAdded: count, tripsUpdated: count, tripsRemoved: count, planVersionsChanged: count))
        let feedback = RefreshFeedback.outcome(result, userInitiated: true)
        let trip = count == 1 ? "trip" : "trips"
        let reis = count == 1 ? "reis" : "reizen"
        #expect(
            feedback.map { $0.text(language: .en) } == [
                "\(count) \(trip) added", "\(count) \(trip) updated", "\(count) \(trip) removed",
            ])
        #expect(
            feedback.map { $0.text(language: .nl) } == [
                "\(count) \(reis) toegevoegd", "\(count) \(reis) bijgewerkt", "\(count) \(reis) verwijderd",
            ])
    }

    @Test func partialSyncDoesNotClaimUpToDate() {
        for result in [
            SyncResult(state: .idle, pendingCount: 1),
            SyncResult(state: .idle, pendingCount: 0, retryAfter: 1),
        ] {
            #expect(RefreshFeedback.outcome(result, userInitiated: true).first?.key == "Something went wrong")
        }
    }

    @Test(arguments: [SyncState.idle, .offline, .failed, .unauthorized, .verificationRequired])
    func automaticSyncNeverProducesFeedback(state: SyncState) async {
        let model = RefreshFeedbackModel()
        let result = SyncResult(state: state, pendingCount: 0, changes: SyncChanges(tripsUpdated: 1))
        #expect(RefreshFeedback.outcome(result, userInitiated: false).isEmpty)
        await model.refresh(userInitiated: false) { result }
        #expect(model.feedback.isEmpty)
        await model.refresh(userInitiated: false) { throw DataFailure.offline }
        #expect(model.feedback.isEmpty)
    }

    @Test func refreshWaitsForSyncAndDismissesItsOutcome() async {
        let model = RefreshFeedbackModel()
        let (stream, completion) = AsyncStream<Void>.makeStream()
        let refresh = Task {
            await model.refresh {
                for await _ in stream { break }
                return SyncResult(state: .idle, pendingCount: 0)
            }
        }
        while !model.refreshing { await Task.yield() }
        #expect(model.feedback.isEmpty)
        await model.refresh {
            Issue.record("Concurrent refresh must not run")
            return nil
        }
        completion.yield()
        completion.finish()
        await refresh.value
        #expect(!model.refreshing)
        #expect(model.feedback.first?.text(language: .en) == "Up to date")
        model.dismiss(presentationID: model.presentationID)
        #expect(model.feedback.isEmpty)
    }

    @Test func anOlderPresentationCannotDismissANewerRefresh() async {
        let model = RefreshFeedbackModel()
        await model.refresh { SyncResult(state: .idle, pendingCount: 0) }
        let previous = model.presentationID
        await model.refresh {
            model.dismiss(presentationID: previous)
            return SyncResult(state: .offline, pendingCount: 0)
        }
        model.dismiss(presentationID: previous)
        #expect(model.feedback.first?.key == "Needs a connection")
        model.dismiss(presentationID: model.presentationID)
        #expect(model.feedback.isEmpty)
    }

    #if DEBUG
        @Test func debugCounterRecordsOnlyAcceptedUserRefreshes() async {
            let model = RefreshFeedbackModel()
            await model.refresh(userInitiated: false) { SyncResult(state: .idle, pendingCount: 0) }
            #expect(model.debugRefreshCount == 0)
            await model.refresh {
                #expect(model.debugRefreshCount == 1)
                await model.refresh {
                    Issue.record("Concurrent refresh must not run")
                    return nil
                }
                return SyncResult(state: .idle, pendingCount: 0)
            }
            #expect(model.debugRefreshCount == 1)
            await model.refresh { throw CancellationError() }
            #expect(model.debugRefreshCount == 2)
        }
    #endif

    @Test func thrownFailuresAndCancellation() async {
        let model = RefreshFeedbackModel()
        await model.refresh { throw DataFailure.offline }
        #expect(model.feedback.first?.key == "Needs a connection")
        await model.refresh { throw DataFailure.server(status: 500) }
        #expect(model.feedback.first?.key == "Something went wrong")
        await model.refresh { throw CancellationError() }
        #expect(model.feedback.isEmpty)
        await model.refresh { nil }
        #expect(model.feedback.isEmpty)
    }

    @Test func finishedSyncIsReportedWhenTheGestureTaskIsCancelled() async {
        let model = RefreshFeedbackModel()
        let task = Task { @MainActor in
            await model.refresh {
                withUnsafeCurrentTask { $0?.cancel() }
                return SyncResult(state: .idle, pendingCount: 0)
            }
        }
        await task.value
        #expect(model.feedback.first?.key == "Up to date")
    }

    @Test func syncKeepsRunningWhenTheGestureTaskIsCancelledMidFlight() async {
        let model = RefreshFeedbackModel()
        let task = Task { @MainActor in
            await model.refresh {
                try await Task.sleep(for: .milliseconds(50))
                return SyncResult(state: .idle, pendingCount: 0)
            }
        }
        task.cancel()
        await task.value
        #expect(model.feedback.first?.key == "Up to date")
    }
}
