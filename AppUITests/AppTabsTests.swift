import DesignSystem
import XCTest

nonisolated final class AppTabsTests: XCTestCase {
    @MainActor func testSignedInAccountCanSwitchAllThreeTabs() throws {
        let app = launchPlanAccount()
        defer { app.terminate() }
        _ = try expandedTabs(in: app, selected: "Today")
        capture(app, name: "today-tabs")
        let progress = app.staticTexts["today.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 4), app.debugDescription)
        _ = try UIWait.stableFrames([progress], timeout: 4)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "today.progress").count, 1)
        XCTAssertEqual(progress.label, "0 of 3 done")
        XCTAssertFalse(app.buttons["today.progress"].exists)
        app.tabBars.buttons["My trips"].tap()
        XCTAssertTrue(app.scrollViews["trips.screen"].waitForExistence(timeout: 4))
        _ = try expandedTabs(in: app, selected: "My trips")
        capture(app, name: "trips-tabs")
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["route.settings"].waitForExistence(timeout: 4))
        _ = try expandedTabs(in: app, selected: "Settings")
        capture(app, name: "settings-tabs")
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.scrollViews["today.screen"].waitForExistence(timeout: 4))
    }

    @MainActor func testTodayTabMinimizesOnScrollDownAndExpandsOnScrollUp() throws {
        try verifyMinimization(tab: "Today", screen: "today.screen", name: "today")
    }

    @MainActor func testTripsTabMinimizesOnScrollDownAndExpandsOnScrollUp() throws {
        try verifyMinimization(tab: "My trips", screen: "trips.screen", name: "trips")
    }

    @MainActor private func verifyMinimization(tab: String, screen: String, name: String) throws {
        guard #available(iOS 26, *) else { throw XCTSkip("System tab minimization requires iOS 26") }
        let app = launchPlanAccount()
        defer { app.terminate() }
        if tab != "Today" { app.tabBars.buttons[tab].tap() }
        let scroll = app.scrollViews[screen]
        XCTAssertTrue(scroll.waitForExistence(timeout: 8))
        XCTAssertEqual(app.scrollViews.matching(identifier: screen).count, 1)
        XCTAssertEqual(scroll.descendants(matching: .scrollView).count, 0, "The tab must have one content scroll view")
        let expanded = try expandedTabs(in: app, selected: tab)
        capture(app, name: "\(name)-tabs")
        let first = scroll.buttons.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 4))
        let anchor = scroll.buttons[first.identifier]
        let initialY = anchor.frame.minY
        var minimized: TabsState?
        for _ in 0..<3 {
            dragContent(in: app, scroll: scroll, down: true)
            minimized = settledTabs(in: app, selected: tab, timeout: 4) { $0.isMinimized(from: expanded) }
            if minimized != nil { break }
        }
        capture(app, name: "\(name)-tabs-minimized")
        XCTAssertTrue(
            !anchor.exists || anchor.frame.minY < initialY - 1 || !anchor.isHittable,
            "The actual tab content must scroll")
        _ = try XCTUnwrap(minimized, "Tab bar did not minimize after scrolling \(tab) down: \(app.debugDescription)")
        let scrolledY = anchor.exists ? anchor.frame.minY : nil
        var restoration: TabsState?
        for _ in 0..<6 {
            dragContent(in: app, scroll: scroll, down: false)
            restoration = settledTabs(in: app, selected: tab, timeout: 4) { $0.isExpanded }
            if restoration != nil { break }
        }
        capture(app, name: "\(name)-tabs-expanded")
        let restored = try XCTUnwrap(restoration, "Tabs stayed collapsed after scrolling up: \(app.debugDescription)")
        XCTAssertTrue(anchor.exists)
        if let scrolledY { XCTAssertGreaterThan(anchor.frame.minY, scrolledY + 1) }
        XCTAssertEqual(restored.bar.width, expanded.bar.width, accuracy: 1)
        XCTAssertEqual(restored.bar.height, expanded.bar.height, accuracy: 1)
        XCTAssertEqual(restored.items.width, expanded.items.width, accuracy: 1)
    }

    @MainActor private func dragContent(in app: XCUIApplication, scroll: XCUIElement, down: Bool) {
        var viewport = AuthUIFlow.viewport(in: app, scrollFrame: scroll.frame)
        let navigation = app.navigationBars.firstMatch
        if navigation.exists {
            let bottom = viewport.maxY
            viewport.origin.y = max(viewport.minY, navigation.frame.maxY)
            viewport.size.height = max(0, bottom - viewport.minY)
        }
        let bar = app.tabBars.firstMatch
        if bar.exists { viewport.size.height = max(0, min(viewport.maxY, bar.frame.minY) - viewport.minY) }
        XCTAssertGreaterThan(viewport.height, 0)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func point(_ fraction: CGFloat) -> XCUICoordinate {
            origin.withOffset(
                CGVector(
                    dx: viewport.midX - app.frame.minX, dy: viewport.minY + viewport.height * fraction - app.frame.minY)
            )
        }
        point(down ? 0.85 : 0.2).press(
            forDuration: 0.05, thenDragTo: point(down ? 0.2 : 0.85), withVelocity: .fast, thenHoldForDuration: 0.1)
    }

    private struct TabsState {
        let bar: CGRect
        let selected: CGRect
        let items: CGRect
        let otherItemsHittable: [Bool]
        let collapsed: Bool
        var isExpanded: Bool { !collapsed && otherItemsHittable.allSatisfy { $0 } }
        func isMinimized(from expanded: Self) -> Bool {
            collapsed || otherItemsHittable.allSatisfy { !$0 }
                || bar.width < expanded.bar.width - 1 || bar.height < expanded.bar.height - 1
                || items.width < expanded.items.width - 1
        }
    }

    @MainActor private func expandedTabs(in app: XCUIApplication, selected: String) throws -> TabsState {
        try XCTUnwrap(
            settledTabs(in: app, selected: selected, timeout: 8) { $0.isExpanded },
            "Three system tabs did not expand with \(selected) selected: \(app.debugDescription)")
    }

    @MainActor private func settledTabs(
        in app: XCUIApplication, selected: String, timeout: TimeInterval, ready: @escaping (TabsState) -> Bool
    ) -> TabsState? {
        var stability = FrameStability()
        var result: TabsState?
        let predicate = NSPredicate { _, _ in
            let bar = app.tabBars.firstMatch
            guard bar.exists else {
                _ = stability.observe(nil)
                return false
            }
            @MainActor func tab(_ label: String) -> XCUIElement? {
                let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
                    .allElementsBoundByIndex.filter { $0.isHittable && bar.frame.contains($0.frame) }
                return matches.count == 1 ? matches[0] : nil
            }
            guard let button = tab(selected), button.isSelected else {
                _ = stability.observe(nil)
                return false
            }
            let others = ["Today", "My trips", "Settings"].filter { $0 != selected }.map(tab)
            let visible = [button] + others.compactMap { $0 }
            let frames = visible.map(\.frame)
            let distinct = Set(frames.map { NSValue(cgRect: $0) }).count == frames.count
            let state = TabsState(
                bar: bar.frame, selected: button.frame, items: frames.reduce(CGRect.null) { $0.union($1) },
                otherItemsHittable: others.map { $0 != nil && distinct },
                collapsed: (button.value as? String)?.contains("Collapsed") == true)
            guard ready(state) else {
                _ = stability.observe(nil)
                return false
            }
            guard stability.observe([state.bar] + frames) else { return false }
            result = state
            return true
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
