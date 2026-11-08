import PlanCore
import PlanUI
import UIKit
import XCTest

nonisolated final class StepSheetLayoutTests: XCTestCase {
    @MainActor func testStepActionsAndLegendScrollWithinEveryLeanProfile() async throws {
        try await AuthTestHost.registerFonts()
        let formatter = try await PlanScreenFixture.formatter()
        let detail = try PlanScreenFixture.detail()
        let block = try XCTUnwrap(detail.plan.blocks.first { $0.actionable && $0.checkKey != nil })
        for fixture in try AuthDeviceFixture.all() where ["se", "17e", "duo"].contains(fixture.name) {
            for language in ["en", "nl"] {
                let host = try AuthTestHost(
                    StepSheet(
                        detail: detail, blockID: block.id, now: PlanScreenFixture.now, formatter: formatter,
                        change: { _ in }),
                    size: fixture.size, insets: fixture.insets, language: language, category: .extraExtraLarge,
                    scale: fixture.scale)
                defer { host.close() }
                try await host.settle()
                try assertPlanScrollFits(host)
                XCTAssertTrue(recoveryTextFields(host.window).isEmpty)
                host.configure(LegendSheet(), language: language, category: .extraExtraLarge)
                try await host.settle()
                try assertPlanScrollFits(host)
            }
        }
    }
}

@MainActor func assertPlanScrollFits(_ host: AuthTestHost) throws {
    let scrolls = authScrollViews(host.controller.view)
    XCTAssertFalse(scrolls.isEmpty)
    for scroll in scrolls where !scroll.isHidden && scroll.bounds.width > 0 {
        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
        let visible = scroll.convert(scroll.bounds, to: host.window)
        let safe = host.container.insets ?? .init(top: 0, left: 0, bottom: 0, right: 0)
        XCTAssertGreaterThanOrEqual(visible.minX, safe.left - 1)
        XCTAssertLessThanOrEqual(visible.maxX, host.window.bounds.width - safe.right + 1)
        scroll.setContentOffset(
            CGPoint(
                x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)),
            animated: false)
        XCTAssertTrue(scroll.contentOffset.y.isFinite)
    }
}
