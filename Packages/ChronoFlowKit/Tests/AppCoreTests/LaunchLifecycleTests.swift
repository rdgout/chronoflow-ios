import Foundation
import Testing

@testable import AppCore

struct LaunchLifecycleTests {
    @Test func firstConnectionIsProcessScoped() {
        var process = LaunchProcessState()
        let first = process.claimOverlay()
        let second = process.claimOverlay()
        let third = process.claimOverlay()
        #expect(first)
        #expect(!second)
        #expect(!third)
        var newProcess = LaunchProcessState()
        let next = newProcess.claimOverlay()
        #expect(next)
    }

    @Test func pendingIntentRetainsAllColdStartInformation() async throws {
        let url = try #require(URL(string: "https://chronoflow.net/trips/42"))
        let payload = Data(#"{"aps":{"alert":"Trip"},"tripId":42}"#.utf8)
        let response = PendingLaunchIntent.Notification(
            requestIdentifier: "reminder", actionIdentifier: "open",
            userInfoJSON: payload, userText: "Later")
        let intent = PendingLaunchIntent(urls: [url], notification: response)
        let copy = await Task.detached { intent }.value
        #expect(copy.urls == [url])
        #expect(copy.notification == response)
        #expect(copy.notification?.userInfoJSON == payload)
        #expect(PendingLaunchIntent().urls.isEmpty)
        #expect(PendingLaunchIntent().notification == nil)
    }

}
