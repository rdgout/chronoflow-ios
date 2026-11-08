import AppCore
import DesignSystem
import PlanCore
import PlanUI
import SwiftUI
import XCTest

nonisolated final class TodayControlTests: XCTestCase {
    @MainActor func testEachRowStateKeepsOneLargeTapTargetAtXXLarge() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        let detail = try PlanScreenFixture.detail()
        let block = try XCTUnwrap(detail.plan.blocks.first { $0.actionable && $0.checkKey != nil })
        let marks: [CheckMark?] = [
            nil, .init(key: block.checkKey!, status: .done, markedAt: block.startUtc),
            .init(key: block.checkKey!, status: .skipped, markedAt: block.startUtc),
        ]
        for fixture in try AuthDeviceFixture.all() where ["se", "17e", "duo"].contains(fixture.name) {
            for language in ["en", "nl"] {
                var frames: [Int: CGRect] = [:]
                let host = try AuthTestHost(
                    ScrollView {
                        VStack {
                            ForEach(0..<marks.count, id: \.self) { index in
                                TodayStepRow(
                                    block: block, mark: marks[index], now: planDate(block.startUtc),
                                    formatter: formatter, trip: detail.trip, running: true, action: {}
                                )
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.onChange(of: geometry.frame(in: .global), initial: true) {
                                            _, frame in frames[index] = frame
                                        }
                                    }
                                }
                            }
                        }.padding(PlanUITokens.space4)
                    }, size: fixture.size, insets: fixture.insets, language: language,
                    category: .extraExtraLarge, scale: fixture.scale)
                defer { host.close() }
                try await host.settle()
                XCTAssertEqual(frames.count, 3)
                for frame in frames.values {
                    XCTAssertGreaterThanOrEqual(frame.height, PlanUITokens.space14)
                    XCTAssertGreaterThanOrEqual(frame.minX, fixture.insets.left + PlanUITokens.space4 - 1)
                    XCTAssertLessThanOrEqual(
                        frame.maxX, fixture.size.width - fixture.insets.right - PlanUITokens.space4 + 1)
                }
            }
        }
    }
}
