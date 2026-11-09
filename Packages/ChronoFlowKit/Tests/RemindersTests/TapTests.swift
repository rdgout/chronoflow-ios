import AppCore
import Foundation
import Testing

@testable import Reminders

@Suite struct ReminderTapTests {
    @Test @MainActor func coldIntentPreservesEndingAndWarmRouterCanReopen() throws {
        let intent = PendingLaunchIntent(
            notification: .capture(
                identifier: "chronoflow.reminder.test", actionIdentifier: "default",
                userInfo: ["url": "chronoflow://trip/trip-id", "blockID": "light", "inputHash": "hash"], userText: nil))
        var state = LaunchState(pendingIntent: intent)
        _ = reduce(&state, .session(.signedIn(accountID: reminderAccount)), reduceMotion: false)
        _ = reduce(&state, .storedData(true), reduceMotion: false)
        _ = reduce(&state, .gate(.app), reduceMotion: false)
        #expect(state.ending == .app)
        #expect(state.route == .today)
        #expect(state.pendingIntent == intent)
        let router = ReminderTapRouter()
        router.receive(state.pendingIntent)
        #expect(router.pending?.blockID == "light")
        router.clear()
        #expect(router.pending == nil)
        router.receive(intent)
        #expect(router.pending?.tripID == "trip-id")
    }

    @Test func capturedJSONAndTripStep() throws {
        let intent = PendingLaunchIntent(
            notification: .capture(
                identifier: "chronoflow.reminder.test", actionIdentifier: "default",
                userInfo: [
                    "url": "chronoflow://trip/trip-id", "blockID": "light", "inputHash": "hash",
                    "accountID": reminderAccount,
                    "reminder": "encoded request",
                ], userText: nil))
        let tap = try #require(ReminderTap(intent: intent))
        #expect(tap.tripID == "trip-id")
        #expect(tap.blockID == "light")
        #expect(tap.inputHash == "hash")
        #expect(tap.accountID == reminderAccount)
        for value in [
            "https://chronoflow.net/trip/trip-id", "chronoflow://trip/", "chronoflow://trip/a/b",
            "chronoflow://trip/a?x=1", "chronoflow://trip/a#b",
        ] {
            let invalid = PendingLaunchIntent(
                notification: .capture(
                    identifier: "test", actionIdentifier: "default", userInfo: ["url": value], userText: nil))
            #expect(ReminderTap(intent: invalid) == nil)
        }
        #expect(ReminderTap(intent: PendingLaunchIntent()) == nil)
    }
}
