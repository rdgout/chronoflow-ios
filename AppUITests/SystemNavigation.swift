import XCTest

@MainActor enum SystemNavigation {
    static func tapBack(in app: XCUIApplication, timeout: TimeInterval = 3) throws {
        let candidates = [app.navigationBars.buttons.firstMatch, app.buttons["BackButton"]]
        var backButton: XCUIElement?
        let ready = { () -> Bool in
            backButton = candidates.first { $0.exists }
            return backButton != nil
        }
        let result = UIWait.until(timeout: timeout, condition: ready)
        let button = try XCTUnwrap(backButton, "System navigation back button did not appear: \(result)")
        button.tap()
    }
}
