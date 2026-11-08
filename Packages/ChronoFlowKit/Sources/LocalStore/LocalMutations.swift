import AppCore
import Foundation
import GRDB

public enum LocalMutationFailure: Error, Sendable, Equatable {
    case unsupported, invalidPayload, missingAccount, missingTrip, onlineOnly
}

extension JSONDocument {
    public static func encoding(_ value: some Encodable) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try Self(String(decoding: encoder.encode(value), as: UTF8.self))
    }
}

extension OutboxRecord {
    public var change: OutboxChange {
        get throws {
            guard let kind = OutboxKind(rawValue: kind) else { throw LocalMutationFailure.invalidPayload }
            let object = try payload.decode(JSONObject.self)
            switch kind {
            case .checkOff: return .checkOff(try payload.decode(CheckOffChange.self))
            case .settings:
                guard let section = object["section"]?.string else { throw LocalMutationFailure.invalidPayload }
                if section == "policies", let version = object["version"]?.string { return .policies(version: version) }
                guard let section = SettingsSection(rawValue: section), let patch = object["patch"]?.object else {
                    throw LocalMutationFailure.invalidPayload
                }
                return .settings(section: section, patch: JSONObject(patch))
            case .profile: return .profile(try payload.decode(ProfileChange.self))
            case .walkthrough: return .walkthrough
            case .completeTrip, .dataExport, .security: return .unsupported(kind: kind, payload: object)
            }
        }
    }

    public var dependency: String {
        let object = try? payload.decode(JSONObject.self)
        if kind == OutboxKind.settings.rawValue { return "settings:\(object?["section"]?.string ?? "unknown")" }
        if kind == OutboxKind.checkOff.rawValue || kind == OutboxKind.completeTrip.rawValue {
            return "trip:\(object?["tripID"]?.string ?? object?["tripId"]?.string ?? "unknown")"
        }
        return kind
    }

    public var referencedTripID: String? {
        let object = try? payload.decode(JSONObject.self)
        return object?["tripID"]?.string ?? object?["tripId"]?.string
    }
}

extension OutboxRepository {
    @discardableResult
    public func enqueue(
        _ change: OutboxChange, permit: SessionMutationPermit? = nil, now: Date = Date(),
        randomBytes: [UInt8] = (0..<10).map { _ in UInt8.random(in: .min ... .max) }
    ) async throws -> OutboxRecord {
        let milliseconds = floor(now.timeIntervalSince1970 * 1000)
        guard milliseconds.isFinite, milliseconds >= 0, milliseconds < Double(1 << 48) else {
            throw LocalMutationFailure.invalidPayload
        }
        let id = try UUIDv7.generate(millisecondsSince1970: UInt64(milliseconds), randomBytes: randomBytes)
            .uuidString.lowercased()
        let createdAt = now.ISO8601Format(.iso8601(timeZone: .gmt, includingFractionalSeconds: true))
        let row = try Self.record(change, id: id, createdAt: createdAt)
        guard let accountID = await database.accountID else { throw StoreFailure.closed }
        return try await database.write(permit: permit) { db in
            var row = row
            guard var account = try AccountRecord.fetchOne(db, key: accountID.rawValue) else {
                throw LocalMutationFailure.missingAccount
            }
            switch change {
            case .checkOff(let check):
                guard let trip = try TripRecord.fetchOne(db, key: check.tripID),
                    !trip.deletedLocally, trip.deletedAt == nil
                else { throw LocalMutationFailure.missingTrip }
                try StoreApplication.setMark(check, at: createdAt, db: db)
            case .settings(let section, let patch):
                var value =
                    try SettingsRecord.fetchOne(db, key: section.rawValue)?.value.decode(JSONObject.self)
                    ?? JSONObject()
                var invalidDrafts = value["invalidDrafts"]?.object ?? [:]
                for (key, entry) in patch.fields {
                    invalidDrafts[key] = nil
                    let parts = key.split(separator: "_")
                    let localKey =
                        String(parts[0]) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
                    value[localKey] = entry
                }
                if section == .bodyClock {
                    value["invalidDrafts"] = .object(invalidDrafts)
                    if patch["habitual_bed"] != nil || patch["habitual_wake"] != nil {
                        try SettingsRecord(section: "sleepAnswered", value: .encoding(true)).save(db)
                    }
                }
                try SettingsRecord(section: section.rawValue, value: .encoding(value)).save(db)
                if section == .bodyClock { try SettingsRecord.deleteOne(db, key: "readiness") }
            case .policies(let version):
                guard var value = try SettingsRecord.fetchOne(db, key: "policies")?.value.decode(JSONObject.self),
                    value["termsVersion"]?.string == version, !version.isEmpty
                else { throw LocalMutationFailure.invalidPayload }
                let pending = try StoreApplication.pending(db).first(where: {
                    $0.dependency == "settings:policies" && (try? $0.change) == .policies(version: version)
                })
                value["acceptedTermsVersion"] = .string(version)
                value["acceptedTermsAt"] = .string(pending?.createdAt ?? createdAt)
                try SettingsRecord(section: "policies", value: .encoding(value)).save(db)
                if let pending { return pending }
            case .profile(let profile):
                guard profile.email.lowercased() == account.email.lowercased() else {
                    throw LocalMutationFailure.onlineOnly
                }
                var payload = try row.payload.decode(JSONObject.self)
                payload["previousName"] = .string(account.name)
                row.payload = try .encoding(payload)
                account.name = profile.name
                try account.save(db)
            case .walkthrough:
                account.walkthroughSeen = true
                try account.save(db)
                if let pending = try StoreApplication.pending(db).first(where: { $0.kind == "walkthrough" }) {
                    return pending
                }
            case .unsupported: throw LocalMutationFailure.unsupported
            }
            try row.insert(db)
            return row
        }
    }

    private static func record(_ change: OutboxChange, id: String, createdAt: String) throws -> OutboxRecord {
        let kind: OutboxKind
        let payload: JSONDocument
        switch change {
        case .checkOff(let value):
            kind = .checkOff
            payload = try .encoding(value)
        case .settings(let section, let patch):
            guard !patch.fields.isEmpty, safeSettings(patch, section: section) else {
                throw LocalMutationFailure.invalidPayload
            }
            kind = .settings
            payload = try .encoding(JSONObject(["section": .string(section.rawValue), "patch": .object(patch.fields)]))
        case .policies(let version):
            kind = .settings
            payload = try .encoding(JSONObject(["section": .string("policies"), "version": .string(version)]))
        case .profile(let value):
            kind = .profile
            payload = try .encoding(value)
        case .walkthrough:
            kind = .walkthrough
            payload = try .encoding(JSONObject())
        case .unsupported: throw LocalMutationFailure.unsupported
        }
        return OutboxRecord(id: id, kind: kind.rawValue, payload: payload, createdAt: createdAt)
    }

    private static func safeSettings(_ patch: JSONObject, section: SettingsSection) -> Bool {
        let allowed: Set<String>
        switch section {
        case .preferences: allowed = ["time_format", "hidden_categories", "show_optional_items"]
        case .reminders: allowed = ["light", "avoid", "caffeine", "winddown", "lead_min"]
        case .bodyClock:
            allowed = [
                "habitual_bed", "habitual_wake", "free_day_status", "free_day_bed", "free_day_wake", "chronotype",
                "age_band", "shift_work", "bipolar", "eye_disease", "pregnancy", "caffeine_ruled_out", "vte",
                "sleep_phase_disorder", "caffeine_habit", "cups_filter_coffee", "cups_tea", "cups_cola",
                "cups_energy_drink", "caffeine_sensitive", "caffeine_non_user_opt_in", "oral_contraception",
                "light_device", "blue_blockers", "blue_blocker_mdfd",
            ]
        }
        return patch.fields.allSatisfy { key, value in
            guard allowed.contains(key) else { return false }
            if case .object = value { return false }
            if case .array(let entries) = value {
                return entries.allSatisfy { if case .string = $0 { true } else { false } }
            }
            return true
        }
    }
}
