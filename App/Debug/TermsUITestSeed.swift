#if DEBUG
    import AppCore
    import LocalStore
    import UIKit

    @MainActor func seedTermsPending(
        database: AccountDatabase, permit: SessionMutationPermit
    ) async throws {
        guard (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true,
            UITestRuntime.environment["CF_AUTH_TEST_TERMS_CHANGES_PENDING"] == "1"
        else { return }
        let outbox = OutboxRepository(database: database)
        guard try await outbox.pending().isEmpty else { return }
        try await outbox.enqueue(
            .settings(section: .preferences, patch: JSONObject(["time_format": .string("12")])), permit: permit)
    }
#endif
