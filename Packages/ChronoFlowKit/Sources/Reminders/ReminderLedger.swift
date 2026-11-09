import CoreFoundation
import Foundation
import LocalStore

public struct ReminderLedgerEntry: Codable, Sendable, Equatable {
    public var tripId: String
    public var inputHash: String
    public var sendAtMs: Double
    public var memberKeys: [String]

    public init(tripId: String, inputHash: String, sendAtMs: Double, memberKeys: [String]) {
        self.tripId = tripId
        self.inputHash = inputHash
        self.sendAtMs = sendAtMs
        self.memberKeys = memberKeys
    }
}

public enum ReminderLedger {
    public static func decode(_ data: Data) -> [ReminderLedgerEntry] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return rows.compactMap { row in
            guard let row = row as? [String: Any], let trip = row["tripId"] as? String,
                let hash = row["inputHash"] as? String, let number = row["sendAtMs"] as? NSNumber,
                CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                let keys = row["memberKeys"] as? [String]
            else { return nil }
            return ReminderLedgerEntry(tripId: trip, inputHash: hash, sendAtMs: number.doubleValue, memberKeys: keys)
        }
    }
    public static func elapsed(_ rows: [ReminderLedgerEntry], now: Date) -> [ReminderLedgerEntry] {
        let milliseconds = now.timeIntervalSince1970 * 1000
        return rows.filter { $0.sendAtMs >= milliseconds - 36 * 60 * 60 * 1000 && $0.sendAtMs <= milliseconds }
    }
    public static func read(database: AccountDatabase) async throws -> [ReminderLedgerEntry] {
        let row = try await SettingsRepository(database: database).settings().first { $0.section == "reminderLedger" }
        return row.map { decode(Data($0.value.rawValue.utf8)) } ?? []
    }
    public static func write(_ rows: [ReminderLedgerEntry], database: AccountDatabase) async throws {
        try await SettingsRepository(database: database).upsert(
            SettingsRecord(section: "reminderLedger", value: .encoding(rows)))
    }
    public static func clear(database: AccountDatabase) async throws {
        try await SettingsRepository(database: database).remove(section: "reminderLedger")
    }
}
