import XCTest

@MainActor enum DeviceAppearance {
    static func set(_ appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.appearance = appearance
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in XCUIDevice.shared.appearance == appearance }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 30) == .completed else {
            throw NSError(domain: "DeviceAppearance", code: 1)
        }
    }
}
