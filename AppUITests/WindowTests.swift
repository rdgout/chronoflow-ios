import XCTest

nonisolated final class WindowTests: XCTestCase {
    @MainActor
    func testOpeningIsOneLocalizedImageElement() {
        let app = XCUIApplication()
        app.launch()
        let opening = app.images["launch.opening"]
        XCTAssertTrue(opening.waitForExistence(timeout: 10))
        XCTAssertTrue(["ChronoFlow is opening", "ChronoFlow wordt geopend"].contains(opening.label))
        XCTAssertEqual(opening.frame, app.frame)
    }

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
