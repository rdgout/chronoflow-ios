import AppCore
import Foundation
import GRDB
import LocalStore

public struct FirstTripRemindersOffer: Sendable {
    private let database: AccountDatabase
    private let permit: SessionMutationPermit?

    public init(database: AccountDatabase, permit: SessionMutationPermit? = nil) {
        self.database = database
        self.permit = permit
    }

    public func queue(firstTrip: Bool) async throws {
        guard firstTrip else { return }
        try await database.write(permit: permit) { db in
            guard try SettingsRecord.fetchOne(db, key: "wizardReminders") == nil else { return }
            try SettingsRecord(section: "wizardReminders", value: .encoding("pending")).insert(db)
        }
    }

    public func consume(permission: ReminderPermission) async throws -> Bool? {
        try Task.checkCancellation()
        return try await database.write(permit: permit) { db in
            guard try SettingsRecord.fetchOne(db, key: "wizardReminders")?.value.decode(String.self) == "pending"
            else { return false }
            guard let settings = try SettingsRecord.fetchOne(db, key: "reminders")?.value.decode(ReminderSettings.self)
            else { return nil }
            // Consume before presentation so recovery and Not now cannot offer the sheet again.
            try SettingsRecord(section: "wizardReminders", value: .encoding("seen")).save(db)
            return permission == .undetermined && settings.enabled
        }
    }
}
