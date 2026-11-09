import DesignSystem
import XCTest

nonisolated final class AppTabsTests: XCTestCase {
    @MainActor func testSignedInAccountCanSwitchAllThreeTabs() throws {
        let app = try launchPlanAccount(freezePlanClock: true)
        defer { app.terminate() }
        try assertTabs(in: app, selected: "Today")
        capture(app, name: "today-tabs")
        let progress = app.staticTexts["today.progress"]
        XCTAssertTrue(progress.waitUntil(.exists, timeout: 4), app.debugDescription)
        _ = try UIWait.stableFrames([progress], timeout: 4)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "today.progress").count, 1)
        XCTAssertFalse(app.buttons["today.progress"].exists)
        XCTAssertEqual(progress.label, "0 of 3 done")
        try tapTab("My trips", in: app)
        XCTAssertTrue(app.scrollViews["trips.screen"].waitUntil(.exists, timeout: 4))
        try assertTabs(in: app, selected: "My trips")
        capture(app, name: "trips-tabs")
        try tapTab("Settings", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.screen"].firstMatch.waitUntil(.exists, timeout: 4))
        try assertTabs(in: app, selected: "Settings")
        capture(app, name: "settings-tabs")
        try tapTab("Today", in: app)
        XCTAssertTrue(app.scrollViews["today.screen"].waitUntil(.exists, timeout: 4))
    }

    @MainActor func testTripsScrollKeepsTheSelectedScreen() throws {
        let app = try launchPlanAccount(freezePlanClock: true)
        defer { app.terminate() }
        try tapTab("My trips", in: app)
        let scroll = app.scrollViews["trips.screen"]
        XCTAssertTrue(scroll.waitUntil(.exists, timeout: 8))
        XCTAssertEqual(app.scrollViews.matching(identifier: "trips.screen").count, 1)
        XCTAssertEqual(scroll.descendants(matching: .scrollView).count, 0)
        scroll.swipeUp()
        XCTAssertTrue(scroll.exists)
        scroll.swipeDown()
        XCTAssertTrue(scroll.exists)
        XCTAssertTrue(tab("My trips", in: app).isSelected)
        capture(app, name: "trips-after-scroll")
    }

    @MainActor private func tab(_ label: String, in app: XCUIApplication) -> XCUIElement {
        // Exact labels exclude the system symbol buttons nested inside Liquid Glass tabs.
        app.tabBars.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor private func tapTab(_ label: String, in app: XCUIApplication) throws {
        let button = tab(label, in: app)
        XCTAssertTrue(button.waitUntil(.exists, timeout: 8), app.debugDescription)
        _ = try UIWait.stableFrames([button], timeout: 4)
        button.tap()
    }

    @MainActor private func assertTabs(in app: XCUIApplication, selected: String) throws {
        let buttons = ["Today", "My trips", "Settings"].map { tab($0, in: app) }
        for button in buttons { XCTAssertTrue(button.waitUntil(.exists, timeout: 8), app.debugDescription) }
        _ = try UIWait.stableFrames(buttons, timeout: 4)
        XCTAssertTrue(tab(selected, in: app).isSelected)
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
