import AppCore
import Foundation
import PlanCore
import Testing

@testable import PlanUI

struct TimelineAccessibilityTests {
    @Test func timeOrderLabelsOptionalFilteringAndContinuations() async throws {
        let detail = try JSONDecoder().decode(
            TripDetail.self,
            from: Data(
                contentsOf: Bundle.module.url(forResource: "detail", withExtension: "json", subdirectory: "Fixtures")!))
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        for language in [Language.en, .nl] {
            let prepared = preparePlan(
                detail, layouts: layoutPlan(detail.plan, timeline: detail.timeline), formatter: formatter,
                language: language)
            for day in prepared.days {
                let dates = day.blocks.map { planDate($0.block.startUtc) }
                #expect(dates == dates.sorted())
                #expect(day.blocks.allSatisfy { !isOptionalStep($0.block) })
                for block in day.blocks {
                    #expect(block.accessibilityLabel.contains(block.title))
                    #expect(block.accessibilityLabel.contains(block.priority))
                    #expect(block.accessibilityLabel.contains(block.interval))
                    if block.continuesBefore {
                        #expect(
                            block.accessibilityLabel.contains(
                                PageCopy(language: language)("Continues from the previous plan day")))
                    }
                    if block.continuesAfter {
                        #expect(
                            block.accessibilityLabel.contains(
                                PageCopy(language: language)("Continues into the next plan day")))
                    }
                }
            }
        }
    }
}
