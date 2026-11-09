import XCTest

nonisolated final class LaunchToWelcomeTests: XCTestCase {
    @MainActor func testLaunchToWelcomeInEachDeviceAppearance() throws {
        let original = XCUIDevice.shared.appearance
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in
            app.terminate()
            try DeviceAppearance.set(original)
        }
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            app.terminate()
            try DeviceAppearance.set(appearance)
            app.launchArguments = ["-cf.session", "out"]
            app.launchMeasured()
            XCTAssertEqual(app.windows.firstMatch.frame, app.frame)
            XCTAssertEqual(app.windows.firstMatch.screenshot().image.size, XCUIScreen.main.screenshot().image.size)
            XCTAssertTrue(app.staticTexts["welcome.wordmark"].waitUntil(.exists, timeout: 30))
            XCTAssertFalse(app.images["launch.opening"].exists)
        }
    }
}
