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
        let outer = scroll.convert(scroll.bounds, to: host.window)
        let adjusted = scroll.adjustedContentInset
        let visible = PlanLayoutEvidence.contentViewport(
            scroll: outer, top: adjusted.top, left: adjusted.left, bottom: adjusted.bottom, right: adjusted.right)
        let safe = host.container.insets ?? .init(top: 0, left: 0, bottom: 0, right: 0)
        let context =
            "window=\(host.window.bounds) safe=\(safe) scroll=\(outer) adjusted=\(adjusted) viewport=\(visible)"
        XCTAssertGreaterThan(visible.width, 0, context)
        XCTAssertGreaterThan(visible.height, 0, context)
        let safeFrame = CGRect(
            x: safe.left, y: safe.top, width: host.window.bounds.width - safe.left - safe.right,
            height: host.window.bounds.height - safe.top - safe.bottom)
        XCTAssertFalse(visible.intersection(safeFrame).isEmpty, context)
        // Native scroll views can underlap chrome; the accessible content must honor the rail.
        var visited: Set<ObjectIdentifier> = []
        var contentCount = 0
        @MainActor func checkContent(_ element: NSObject) {
            guard visited.insert(ObjectIdentifier(element)).inserted else { return }
            if let identifier = (element as? any UIAccessibilityIdentification)?.accessibilityIdentifier,
                [
                    "plan.text.", "today.step.", "today.trip", "today.progress", "trip.", "trips.section.",
                    "plan.loading", "trips.loading",
                ].contains(where: identifier.hasPrefix),
                element.isAccessibilityElement
            {
                let frame = host.window.convert(element.accessibilityFrame, from: nil)
                if !frame.isEmpty && !frame.isInfinite {
                    contentCount += 1
                    XCTAssertGreaterThanOrEqual(frame.minX, safe.left - 1, "\(identifier) frame=\(frame) \(context)")
                    XCTAssertLessThanOrEqual(
                        frame.maxX, host.window.bounds.width - safe.right + 1,
                        "\(identifier) frame=\(frame) \(context)")
                }
            }
            if let view = element as? UIView { view.subviews.forEach(checkContent) }
            if let elements = element.accessibilityElements {
                elements.compactMap { $0 as? NSObject }.forEach(checkContent)
            }
            let count = element.accessibilityElementCount()
            if count > 0 && count != NSNotFound {
                for index in 0..<count {
                    if let child = element.accessibilityElement(at: index) as? NSObject { checkContent(child) }
                }
            }
        }
        checkContent(scroll)
        XCTAssertGreaterThan(contentCount, 0, "Missing accessible content: \(context)")
        scroll.setContentOffset(
            CGPoint(
                x: -adjusted.left,
                y: max(-adjusted.top, scroll.contentSize.height - scroll.bounds.height + adjusted.bottom)),
            animated: false)
        XCTAssertTrue(scroll.contentOffset.y.isFinite)
    }
}
