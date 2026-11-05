import XCTest

nonisolated final class WindowTests: XCTestCase {
    @MainActor
    func testWindowFillsScreen() {
        let app = XCUIApplication()
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(window.frame, app.frame)
        XCTAssertEqual(window.screenshot().image.size, XCUIScreen.main.screenshot().image.size)
    }
}
