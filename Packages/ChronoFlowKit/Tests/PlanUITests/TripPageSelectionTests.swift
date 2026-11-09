import Foundation
import LocalStore
import PlanCore
import Sync
import Testing

@testable import AppCore
@testable import PlanUI

struct TripPageSelectionTests {
    @Test @MainActor func selectionKeepsTheTappedBlockAndLiveChecksThroughReplacementAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = AccountDatabase(applicationSupport: root)
        let accountID = "00000000-0000-4000-8000-000000000018"
        try await database.open(accountID: accountID)
        try await AccountRepository(database: database).upsert(
            AccountRecord(id: accountID, name: "Test", email: "test@example.com"))
        var detail = try ModelTests().detail()
        let block = try #require(detail.plan.blocks.first { $0.actionable && $0.checkKey != nil })
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        let repository = TripRepository(database: database)
        try await repository.upsert(
            TripRecord(
                id: detail.trip.id, card: .encoding(ModelTests().recoveryCard(detail)),
                currentInputHash: detail.plan.meta.inputHash, departureUtc: detail.trip.departureUtc))
        var record = PlanVersionRecord(
            tripId: detail.trip.id, inputHash: detail.plan.meta.inputHash, detail: try .encoding(detail),
            receivedAt: block.startUtc, detailVersion: detail.detailVersion)
        try await repository.store(plan: record, checks: [])
        let model = TripPageModel(
            tripID: detail.trip.id, repository: repository, retention: PlanRetention(), path: nil,
            clock: TestPlanClock(planDate(block.startUtc)), now: planDate(block.startUtc),
            mutationPermit: SessionMutationPermit())
        model.start()
        defer { model.stop() }
        try await ModelTests().eventually { model.plan.prepared != nil }
        #expect(model.selectedStep == nil)
        model.selectBlock(block.id, formatter: formatter)
        let selection = try #require(model.selectedStep)
        #expect(selection.id == block.id)
        #expect(selection.blockID == block.id)
        #expect(
            selection.formatter.format(block.text, options: CopyFormat(language: .en))
                == formatter.format(block.text, options: CopyFormat(language: .en)))
        model.timeline = false
        model.select(dayID: detail.plan.days.last!.id)
        #expect(model.selectedStep?.id == selection.id)
        for status: CheckStatus? in [.done, nil, .skipped] {
            try await model.plan.setCheck(blockID: selection.blockID, status: status)
            try await ModelTests().eventually {
                model.plan.detail?.checkState.marks.first { $0.key == block.checkKey }?.status == status
            }
            #expect(model.selectedStep?.id == selection.id)
        }
        model.selectedStep = nil
        model.selectBlock(block.id, formatter: formatter)
        #expect(model.selectedStep?.id == selection.id)
        #expect(model.plan.detail?.checkState.marks.first { $0.key == block.checkKey }?.status == .skipped)
        detail.plan.blocks.removeAll { $0.id == block.id }
        detail.detailVersion += "-removed"
        record.detail = try .encoding(detail)
        record.detailVersion = detail.detailVersion
        try await repository.store(plan: record, checks: [])
        try await ModelTests().eventually { model.plan.detail?.detailVersion == detail.detailVersion }
        #expect(model.selectedStep?.id == selection.id)
        #expect(model.plan.detail?.plan.blocks.contains { $0.id == selection.blockID } == false)
        let pending = try await OutboxRepository(database: database).pending().count
        try await model.plan.setCheck(blockID: selection.blockID, status: .done)
        #expect(try await OutboxRepository(database: database).pending().count == pending)
        try await database.write { try $0.execute(sql: "DELETE FROM plan_versions") }
        try await ModelTests().eventually { model.plan.detail == nil }
        #expect(model.selectedStep?.blockID == block.id)
        model.stop()
        #expect(model.selectedStep == nil)
        try await database.close()
    }
}
