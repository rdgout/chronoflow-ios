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

    @Test func capturesValidNotificationJSONAndResponseMetadata() throws {
        let response = PendingLaunchIntent.Notification.capture(
            identifier: "reminder", actionIdentifier: "reply",
            userInfo: ["tripId": 42, "aps": ["alert": "Trip"], "items": [true, NSNull()]], userText: "Later")
        #expect(response.requestIdentifier == "reminder")
        #expect(response.actionIdentifier == "reply")
        #expect(response.userText == "Later")
        let data = try #require(response.userInfoJSON)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["tripId"] as? Int == 42)
        #expect((payload["aps"] as? [String: String])?["alert"] == "Trip")
        #expect(data == Data(#"{"aps":{"alert":"Trip"},"items":[true,null],"tripId":42}"#.utf8))
        let empty = PendingLaunchIntent.Notification.capture(
            identifier: "empty", actionIdentifier: "open", userInfo: [:], userText: nil)
        #expect(empty.userInfoJSON == Data("{}".utf8))
        #expect(empty.userText == nil)
    }

    @Test func capturesNonJSONNotificationPayloadsWithoutSerializingThem() {
        let payloads: [[AnyHashable: Any]] = [
            ["date": Date(timeIntervalSince1970: 0)],
            ["data": Data([0, 1, 255])],
            [42: "non-string key"],
            ["nested": ["values": [Date(timeIntervalSince1970: 0)]]],
            ["number": Double.nan],
        ]
        for payload in payloads {
            let response = PendingLaunchIntent.Notification.capture(
                identifier: "reminder", actionIdentifier: "reply", userInfo: payload, userText: "Later")
            #expect(response.userInfoJSON == nil)
            #expect(response.requestIdentifier == "reminder")
            #expect(response.actionIdentifier == "reply")
            #expect(response.userText == "Later")
        }
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
