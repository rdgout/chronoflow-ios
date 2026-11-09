import AppCore
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class AuthUniversalLinkTests: XCTestCase {
    @MainActor func testColdCaptureAndWarmActivityPreserveResetInputWithoutAScheme() throws {
        let scene = SceneDelegate()
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = try XCTUnwrap(
            URL(string: "https://app.chronoflow.net/reset-password/token%252F?email=a%2Bb%40example.com"))
        scene.captureAuthActivities([activity])
        XCTAssertEqual(scene.pendingAuthLink, .reset(ResetPasswordLink(token: "token%2F", email: "a+b@example.com")))
        let warm = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        warm.webpageURL = try XCTUnwrap(
            URL(string: "https://app.chronoflow.net/reset-password?email=expired%40example.com"))
        scene.captureAuthActivities([warm])
        XCTAssertEqual(scene.pendingAuthLink, .reset(ResetPasswordLink(token: "", email: "expired@example.com")))
        scene.consumePendingAuthLink()
    }
}
