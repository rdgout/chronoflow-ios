import AppCore
import DataAccess
import Foundation
import LocalStore
import PlanUI
import Sync
import Testing

@Suite @MainActor struct RefusedChangeTests {
    @Test(arguments: [false, true])
    func serverRefusalProducesTheDrawnMessage(step: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try AccountID("00000000-0000-4000-8000-000000000016")
        let database = AccountDatabase(applicationSupport: root)
        try await database.open(accountID: id.rawValue)
        try await AccountRepository(database: database).upsert(
            AccountRecord(id: id.rawValue, name: "Test", email: "test@example.com"))
        let detail = try ModelTests().detail()
        try await TripRepository(database: database).upsert(
            TripRecord(
                id: detail.trip.id, card: .encoding(ModelTests().recoveryCard(detail)),
                currentInputHash: detail.plan.meta.inputHash, departureUtc: detail.trip.departureUtc))
        let model = RefusedChangeModel()
        #expect(model.text(language: .en) == nil)
        let change: OutboxChange =
            step
            ? .checkOff(
                CheckOffChange(
                    tripID: detail.trip.id, planInputHash: detail.plan.meta.inputHash, type: .avoidLight,
                    localDate: "2026-11-10", ordinal: 1, status: .done))
            : .settings(section: .bodyClock, patch: JSONObject(["habitual_bed": .string("22:00")]))
        let row = try await OutboxRepository(database: database).enqueue(change)
        let source = MockDataSource(sleep: { _ in })
        await source.failNext(method: .send, error: .server(status: 422))
        let result = try await OutboxFlusher(database: database, source: source, prepareCheck: { row, _ in row })
            .run(epoch: SyncEpoch(accountID: id, generation: 1))
        let refused = try #require(result.refusals.first)
        #expect(refused.id == row.id)
        model.receive(SyncResult(state: .failed, pendingCount: 0, retryAfter: 1, refusals: result.refusals))
        #expect(model.text(language: .en) == nil)
        model.receive(SyncResult(state: .idle, pendingCount: 0))
        #expect(model.refusal == refused)
        #expect(try await OutboxRepository(database: database).pending().isEmpty)
        #expect(
            model.text(language: .en)
                == (step
                    ? "Couldn't save \"Avoid bright light\" as done, so we undid it."
                    : "Couldn't save your sleep times, so we undid the change."))
        #expect(
            model.text(language: .nl)
                == (step
                    ? "\"Vermijd fel licht\" kon niet als gedaan worden opgeslagen, dus hebben we dat teruggedraaid."
                    : "Je slaaptijden konden niet worden opgeslagen, dus hebben we de wijziging teruggedraaid."))
        model.clear()
        #expect(model.refusal == nil && model.text(language: .nl) == nil)
        try await database.close()
    }
}
