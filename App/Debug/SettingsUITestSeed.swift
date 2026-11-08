#if DEBUG
    import AppCore
    import LocalStore
    import Sync
    import UIKit

    @MainActor func seedSettingsPending(
        native: NativeSessionController, database: AccountDatabase, snapshot: SessionSnapshot,
        permit: SessionMutationPermit
    ) async {
        guard (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true,
            ProcessInfo.processInfo.environment["CF_SETTINGS_TEST_PENDING"] == "1"
        else { return }
        for _ in 0..<100 {
            guard !Task.isCancelled, await native.controller.activeSession() == snapshot else { return }
            if let result = try? await native.sync?.refreshNow(), result.state == .idle { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        await native.sync?.stop()
        guard await native.controller.activeSession() == snapshot,
            let account = try? await AccountRepository(database: database).account(),
            account.email == "demo@example.com"
        else { return }
        let trips = TripRepository(database: database)
        guard let trip = try? await trips.trips().first(where: { $0.currentInputHash != nil }),
            let hash = trip.currentInputHash,
            let plan = try? await trips.plan(tripID: trip.id, inputHash: hash),
            let detail = try? plan.detail.decode(TripDetail.self),
            let block = detail.plan.blocks.first(where: { $0.actionable && $0.checkKey != nil }),
            let key = block.checkKey
        else { return }
        _ = try? await OutboxRepository(database: database).enqueue(
            .checkOff(
                CheckOffChange(
                    tripID: trip.id, planInputHash: hash, type: key.type,
                    localDate: key.localDate, ordinal: key.ordinal, status: .done)), permit: permit)
    }
#endif
