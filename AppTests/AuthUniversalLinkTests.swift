import AppCore
import UIKit
import XCTest

@testable import ChronoFlow

nonisolated final class AuthUniversalLinkTests: XCTestCase {
    @MainActor func testSignedColdAndWarmBrowsingActivitiesReachTheSameRouter() throws {
        let scene = SceneDelegate()
        var received: [AuthLink] = []
        scene.authLinkHandler = { received.append($0) }
        let input = SignedVerificationInput(
            id: "0199a3c0-0000-7000-8000-000000000001", hash: String(repeating: "a", count: 40), expires: 1_800_000_000,
            signature: String(repeating: "b", count: 64))
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = URL(
            string:
                "https://app.chronoflow.net/email/verify/\(input.id)/\(input.hash)?expires=\(input.expires)&signature=\(input.signature)"
        )
        scene.captureAuthActivities([activity])
        XCTAssertTrue(received.isEmpty)
        scene.consumePendingAuthLink()
        XCTAssertEqual(received, [.verify(input)])
        let connected = try XCTUnwrap(UIApplication.shared.connectedScenes.first)
        scene.scene(connected, continue: activity)
        XCTAssertEqual(received, [.verify(input), .verify(input)])
    }
    @MainActor func testColdCaptureAndWarmActivityPreserveResetInputWithoutAScheme() throws {
        let scene = SceneDelegate()
        var received: [AuthLink] = []
        scene.authLinkHandler = { received.append($0) }
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
        XCTAssertEqual(received, [.reset(ResetPasswordLink(token: "", email: "expired@example.com"))])
    }
}
