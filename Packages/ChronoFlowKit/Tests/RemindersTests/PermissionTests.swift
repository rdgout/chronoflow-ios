import Foundation
import PlanCore
import Testing
import UserNotifications

@testable import Reminders

@Suite struct ReminderPermissionTests {
    @Test(arguments: ReminderPermission.allCases)
    func mockAuthorizationChangesOnlyAfterAnExplicitRequest(permission: ReminderPermission) async throws {
        let center = MockReminderCenter(permission: permission)
        #expect(await center.permission() == permission)
        #expect(await center.permissionRequestCount == 0)
        #expect(await center.requestPermission() == (permission == .undetermined ? .granted : permission))
        #expect(await center.permissionRequestCount == 1)
    }

    @Test func permissionMatrix() {
        for permission in ReminderPermission.allCases {
            #expect(permission.remindersActive(ReminderSettings()) == (permission == .granted))
            #expect(!permission.remindersActive(nil))
            #expect(!permission.remindersActive(ReminderSettings().settingEnabled(false)))
        }
    }
    @Test func absoluteTriggersSurviveDSTAndDeviceZoneChanges() {
        for value in ["2027-03-28T01:30:00Z", "2027-10-31T01:30:00Z", "2027-11-07T06:30:00Z"] {
            let date = planDate(value)
            let trigger = SystemReminderCenter.trigger(for: date)
            #expect(!trigger.repeats)
            #expect(trigger.dateComponents.timeZone == .gmt)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
            #expect(calendar.date(from: trigger.dateComponents) == date)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            #expect(calendar.date(from: trigger.dateComponents) == date)
        }
    }
    @Test func nativeAuthorizationMatrix() {
        #expect(SystemReminderCenter.permission(.notDetermined) == .undetermined)
        #expect(SystemReminderCenter.permission(.denied) == .blocked)
        #expect(SystemReminderCenter.permission(.authorized) == .granted)
        #expect(SystemReminderCenter.permission(.provisional) == .granted)
    }

}
