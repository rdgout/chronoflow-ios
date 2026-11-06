import UIKit
import XCTest

nonisolated final class AppIconTests: XCTestCase {
    @MainActor
    func testBuiltAppDeclaresThePrimaryAppIcon() throws {
        let icons = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertFalse(try XCTUnwrap(primary["CFBundleIconFiles"] as? [String]).isEmpty)
    }
}
