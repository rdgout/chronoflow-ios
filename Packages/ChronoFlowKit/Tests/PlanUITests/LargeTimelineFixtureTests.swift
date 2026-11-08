import AppCore
import DataAccess
import Foundation
import PlanCore
import Testing

@testable import PlanUI

struct LargeTimelineFixtureTests {
    @Test func generatedTripsStayDenseAndResolveExistingCopy() async throws {
        let catalog = try await CopyCatalog.load()
        let formatter = CopyLineFormatter(catalog: catalog)
        for count in [30, 60] {
            let fixture = try MockTimelineFixtures.fixture(named: "large\(count)")
            let detail = fixture.detail
            #expect(detail.plan.days.count == count)
            #expect(Set(detail.plan.days.map(\.id)).count == count)
            #expect(Set(detail.plan.blocks.map(\.id)).count == detail.plan.blocks.count)
            #expect(Set(detail.plan.days.flatMap(\.zones).map(\.tz)).count >= 3)
            #expect(detail.plan.blocks.filter { $0.type == .zoneChange }.count >= count / 6)
            #expect(detail.plan.blocks.filter { $0.lane == .sleep }.count >= count)
            #expect(detail.plan.blocks.filter { $0.lane == .light }.count >= count)
            #expect(detail.plan.blocks.filter { $0.lane == .caffeine }.count >= count)
            #expect(
                detail.plan.blocks.contains {
                    if case .flight(let p) = $0.params { return p.overnight }
                    return false
                })
            for (a, b) in zip(detail.plan.days, detail.plan.days.dropFirst()) { #expect(a.endUtc == b.startUtc) }
            for block in detail.plan.blocks {
                #expect(planDate(block.startUtc) <= planDate(block.endUtc))
                #expect(catalog.contains(block.text.key))
                if let secondary = block.secondaryText { #expect(catalog.contains(secondary.key)) }
            }
            for language in [Language.en, .nl] {
                let prepared = preparePlan(
                    detail, layouts: layoutPlan(detail.plan, timeline: detail.timeline), formatter: formatter,
                    language: language)
                #expect(prepared.days.count == count)
                #expect(prepared.days.allSatisfy { !$0.blocks.isEmpty })
            }
        }
    }

    @Test func defaultMockHasNoPerformanceTrips() throws {
        #if DEBUG
            let original = try MockAppSeed.make(now: Date())
            let expanded = try MockAppSeed.make(now: Date(), includeTimelinePerformanceTrips: true)
            let id = "0199a3c0-0000-7000-8000-000000000000"
            #expect(original.accounts[id]?.trips.count == 7)
            #expect(expanded.accounts[id]?.trips.count == 9)
        #endif
    }
}
