import XCTest

@MainActor enum SystemNavigation {
    static func tapBack(in app: XCUIApplication, timeout: TimeInterval = 3) throws {
        let candidates = [app.navigationBars.buttons.firstMatch, app.buttons["BackButton"]]
        var backButton: XCUIElement?
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                backButton = candidates.first { $0.exists }
                return backButton != nil
            }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: timeout)
        let button = try XCTUnwrap(backButton, "System navigation back button did not appear: \(result)")
        button.tap()
    }
}
