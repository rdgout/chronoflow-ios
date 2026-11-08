import AppCore
import PlanCore
import PlanUI
import SwiftUI
import XCTest

nonisolated final class StepSheetSnapshotTests: XCTestCase {
    enum State: String, CaseIterable { case running, upcoming, done, skipped, information, gone, legend }
    @MainActor func testStepSheetStates() async throws {
        let formatter = try await PlanScreenFixture.formatter()
        let original = try PlanScreenFixture.detail()
        try await planSnapshots("StepSheet", states: State.allCases) { state in
            var detail = original
            var block = detail.plan.blocks.first { $0.actionable && $0.checkKey != nil }!
            if state == .information {
                block.actionable = false
                block.checkKey = nil
                block.priority = .info
            }
            detail.plan.blocks = [block]
            if let key = block.checkKey, state == .done || state == .skipped {
                detail.checkState.marks = [
                    CheckMark(key: key, status: state == .done ? .done : .skipped, markedAt: block.startUtc)
                ]
            } else {
                detail.checkState.marks = []
            }
            return StepOrLegendFixture(
                legend: state == .legend, detail: state == .gone ? nil : detail, blockID: block.id,
                now: state == .upcoming ? planDate(block.startUtc).addingTimeInterval(-60) : planDate(block.startUtc),
                formatter: formatter)
        }
    }
}

private struct StepOrLegendFixture: View {
    let legend: Bool
    let detail: TripDetail?
    let blockID: String
    let now: Date
    let formatter: CopyLineFormatter
    var body: some View {
        if legend {
            LegendSheet()
        } else {
            StepSheet(detail: detail, blockID: blockID, now: now, formatter: formatter, change: { _ in })
        }
    }
}
