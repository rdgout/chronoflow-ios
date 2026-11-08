import AppCore
import DataAccess
import Foundation
import PlanCore
import XCTest

@testable import PlanUI

nonisolated final class TimelinePerformanceTests: XCTestCase {
    private var sink = 0
    func testS3DecodeLayoutAndPreparation() async throws { try await benchmark("S3", budget: 0.04) }
    func test30DayDecodeLayoutAndPreparation() async throws { try await benchmark("large30", budget: 0.1) }
    func test60DayDecodeLayoutAndPreparation() async throws { try await benchmark("large60", budget: 0.2) }

    private func benchmark(_ name: String, budget: TimeInterval) async throws {
        let fixture = try MockTimelineFixtures.fixture(named: name)
        let data = try JSONEncoder().encode(fixture.detail)
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        measure {
            do {
                let start = ContinuousClock.now
                let detail = try JSONDecoder().decode(TripDetail.self, from: data)
                let layouts = layoutPlan(detail.plan, timeline: detail.timeline)
                let prepared = preparePlan(detail, layouts: layouts, formatter: formatter, language: .en)
                sink = prepared.days.reduce(0) { $0 + $1.blocks.count }
                XCTAssertGreaterThan(sink, 0)
                XCTAssertLessThan(
                    start.duration(to: .now), .seconds(budget),
                    "\(name) decode + index/layout + preparation budget (Debug and Release)")
            } catch { XCTFail(String(describing: error)) }
        }
    }
}
