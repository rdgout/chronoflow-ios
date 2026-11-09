#if DEBUG
    import AppCore
    import LocalStore
    import Sync
    import UIKit

    @MainActor func seedSettingsPending(
        native: NativeSessionController, database: AccountDatabase, snapshot: SessionSnapshot,
        permit: SessionMutationPermit
    ) async throws {
        guard (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true,
            UITestRuntime.environment["CF_SETTINGS_TEST_PENDING"] == "1"
        else { return }
        guard let account = try await AccountRepository(database: database).account(),
            account.email == "demo@example.com"
        else { return }
        var ready = false
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard await native.controller.activeSession() == snapshot else { return }
            if let result = try await native.sync?.refreshNow(), result.state == .idle {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard ready else { throw SettingsSeedFailure.initialSyncUnavailable }
        let trips = TripRepository(database: database)
        for trip in try await trips.trips() where trip.deletedAt == nil && !trip.deletedLocally {
            guard let hash = trip.currentInputHash,
                let plan = try await trips.plan(tripID: trip.id, inputHash: hash),
                let key = try plan.detail.decode(TripDetail.self).plan.blocks.first(where: {
                    $0.actionable && $0.checkKey != nil
                })?.checkKey
            else { continue }
            let outbox = OutboxRepository(database: database)
            let row = try await outbox.enqueue(
                .checkOff(
                    CheckOffChange(
                        tripID: trip.id, planInputHash: hash, type: key.type,
                        localDate: key.localDate, ordinal: key.ordinal, status: .done)), permit: permit)
            guard try await outbox.pending().contains(where: { $0.id == row.id }) else {
                throw SettingsSeedFailure.missingPendingChange
            }
            return
        }
        throw SettingsSeedFailure.noCachedActionableStep
    }

    private enum SettingsSeedFailure: Error {
        case initialSyncUnavailable, noCachedActionableStep, missingPendingChange
    }
#endif
