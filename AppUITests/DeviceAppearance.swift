import XCTest

@MainActor enum DeviceAppearance {
    static func set(_ appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.appearance = appearance
        let ready = { () -> Bool in
            XCUIDevice.shared.appearance == appearance
        }
        guard UIWait.until(timeout: 30, condition: ready) else {
            throw NSError(domain: "DeviceAppearance", code: 1)
        }
    }
}
