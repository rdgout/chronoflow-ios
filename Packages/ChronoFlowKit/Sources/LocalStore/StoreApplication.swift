import AppCore
import GRDB

public enum StoreApplication {
    public static func pending(_ db: Database) throws -> [OutboxRecord] {
        try OutboxRecord.fetchAll(db, sql: "SELECT * FROM outbox ORDER BY created_at,id")
    }

    public static func identity(_ value: AccountIdentity, accountID: AccountID, db: Database) throws {
        guard value.id == accountID.rawValue else { throw StoreFailure.invalidAccountID }
        let rows = try pending(db)
        var record =
            try AccountRecord.fetchOne(db, key: value.id)
            ?? AccountRecord(id: value.id, name: value.name, email: value.email)
        if !rows.contains(where: { $0.kind == "profile" }) {
            record.name = value.name
            record.email = value.email
        }
        record.hasVerifiedEmail = value.hasVerifiedEmail
        record.walkthroughSeen = value.walkthroughSeen || rows.contains(where: { $0.kind == "walkthrough" })
        try record.save(db)
        try setting("policies", value: .encoding(value.policies), db: db)
    }

    public static func snapshot(_ value: AccountSnapshot, accountID: AccountID, db: Database) throws {
        guard value.id == accountID.rawValue else { throw StoreFailure.invalidAccountID }
        let rows = try pending(db)
        guard var record = try AccountRecord.fetchOne(db, key: value.id) else {
            throw LocalMutationFailure.missingAccount
        }
        if !rows.contains(where: { $0.kind == "profile" }) {
            record.name = value.name
            record.email = value.email
        }
        record.hasVerifiedEmail = value.hasVerifiedEmail
        try record.save(db)
        for (section, document) in try [
            ("bodyClock", JSONDocument.encoding(value.settings.bodyClock)),
            ("preferences", .encoding(value.settings.preferences)), ("reminders", .encoding(value.settings.reminders)),
            ("planCredits", .encoding(value.settings.planCredits)), ("policies", .encoding(value.settings.policies)),
            ("sleepAnswered", .encoding(value.settings.sleepAnswered)), ("billing", .encoding(value.billing)),
            ("security", .encoding(value.security)),
        ] { try setting(section, value: document, db: db) }
        if rows.contains(where: { $0.dependency == "settings:bodyClock" }) {
            try SettingsRecord.deleteOne(db, key: "readiness")
        } else {
            try setting("readiness", value: .encoding(value.readiness), db: db)
        }
    }

    public static func setting(_ section: String, value: JSONDocument, db: Database) throws {
        let rows = try pending(db).filter { $0.dependency == "settings:\(section)" }
        if section == "policies", let latest = rows.last, case .policies(let version) = try latest.change {
            var policies = try value.decode(JSONObject.self)
            policies["acceptedTermsVersion"] = .string(version)
            policies["acceptedTermsAt"] = .string(latest.createdAt)
            try SettingsRecord(section: section, value: .encoding(policies)).save(db)
            return
        }
        guard rows.isEmpty else { return }
        try SettingsRecord(section: section, value: value).save(db)
    }

    public static func checks(_ value: CheckState, tripID: String, db: Database) throws {
        guard !(try pending(db)).contains(where: { $0.kind == "check-off" && $0.referencedTripID == tripID }) else {
            return
        }
        try db.execute(
            sql: "DELETE FROM check_marks WHERE trip_id=? AND input_hash=?", arguments: [tripID, value.planInputHash])
        for mark in value.marks {
            try CheckMarkRecord(
                tripId: tripID, inputHash: value.planInputHash, type: mark.key.type.rawValue,
                localDate: mark.key.localDate, ordinal: mark.key.ordinal, status: mark.status.rawValue,
                markedAt: mark.markedAt
            ).save(db)
        }
    }

    public static func setMark(_ value: CheckOffChange, at: String, db: Database) throws {
        if let status = value.status {
            try CheckMarkRecord(
                tripId: value.tripID, inputHash: value.planInputHash, type: value.type.rawValue,
                localDate: value.localDate, ordinal: value.ordinal, status: status.rawValue, markedAt: at
            ).save(db)
        } else {
            try db.execute(
                sql:
                    "DELETE FROM check_marks WHERE trip_id=? AND input_hash=? AND type=? AND local_date=? AND ordinal=?",
                arguments: [value.tripID, value.planInputHash, value.type.rawValue, value.localDate, value.ordinal])
        }
    }

    public static func refuse(_ row: OutboxRecord, accountID: AccountID, db: Database) throws {
        try OutboxRecord.deleteOne(db, key: row.id)
        guard row.kind == "profile", let previous = try row.payload.decode(JSONObject.self)["previousName"]?.string
        else { return }
        if var next = try pending(db).first(where: { $0.kind == "profile" }) {
            var payload = try next.payload.decode(JSONObject.self)
            payload["previousName"] = .string(previous)
            next.payload = try .encoding(payload)
            try next.save(db)
        } else {
            try db.execute(sql: "UPDATE account SET name=? WHERE id=?", arguments: [previous, accountID.rawValue])
        }
    }

    public static func receipt(_ value: MutationReceipt, for row: OutboxRecord, accountID: AccountID, db: Database)
        throws
    {
        try OutboxRecord.deleteOne(db, key: row.id)
        switch value {
        case .acknowledged: break
        case .account(let value): try snapshot(value, accountID: accountID, db: db)
        case .identity(let value): try identity(value, accountID: accountID, db: db)
        case .checks(let value):
            guard let tripID = row.referencedTripID else { throw LocalMutationFailure.invalidPayload }
            try checks(value.checkState, tripID: tripID, db: db)
            try db.execute(
                sql:
                    "UPDATE plan_versions SET detail_version=NULL WHERE trip_id=? AND input_hash=? AND detail_version!=?",
                arguments: [tripID, value.checkState.planInputHash, value.detailVersion])
        }
    }
}
