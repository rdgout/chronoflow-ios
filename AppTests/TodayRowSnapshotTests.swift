#if DEBUG
    import AppCore
    import DesignSystem
    import PlanCore
    import PlanUI
    import SwiftUI
    import XCTest

    nonisolated final class TodayRowSnapshotTests: XCTestCase {
        enum State: String { case rows }
        @MainActor func testRunningDoneAndSkippedRowsAsOnTheRowStatesBoard() async throws {
            let formatter = try await PlanScreenFixture.formatter()
            let detail = try PlanScreenFixture.detail()
            let block = try XCTUnwrap(detail.plan.blocks.first { $0.actionable && $0.checkKey != nil })
            try await planSnapshots("TodayRows", states: [State.rows]) { _ in
                ScrollView {
                    VStack(spacing: PlanUITokens.space3) {
                        TodayStepRow(
                            block: block, mark: nil, now: planDate(block.startUtc), formatter: formatter,
                            trip: detail.trip, running: true, action: {})
                        TodayStepRow(
                            block: block,
                            mark: CheckMark(key: block.checkKey!, status: .done, markedAt: block.startUtc),
                            now: planDate(block.startUtc), formatter: formatter, trip: detail.trip, running: true,
                            action: {})
                        TodayStepRow(
                            block: block,
                            mark: CheckMark(key: block.checkKey!, status: .skipped, markedAt: block.startUtc),
                            now: planDate(block.startUtc), formatter: formatter, trip: detail.trip, running: true,
                            action: {})
                    }.padding(PlanUITokens.space4)
                }.background(ColorToken.card.color)
            }
        }
    }
#endif
