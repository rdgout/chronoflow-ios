import UIKit
import XCTest

nonisolated enum WizardLayoutTestSupport {
    static func profile(_ name: String) throws -> AuthDeviceFixture {
        try XCTUnwrap(try AuthDeviceFixture.all().first { $0.name == name })
    }

    // AuthTestHost cannot pass horizontal insets through NavigationStack; Duo rail fit is checked on the Duo runtime.
    static func assertVerticallyContained(
        _ frame: CGRect, in container: CGRect, tolerance: CGFloat = 0, context: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(frame.minY, container.minY - tolerance, context, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, container.maxY + tolerance, context, file: file, line: line)
    }
}
