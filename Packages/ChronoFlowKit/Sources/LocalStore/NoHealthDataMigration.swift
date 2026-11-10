import AppCore
import Foundation
import GRDB

enum NoHealthDataMigration {
    static func migrate(_ db: Database) throws {
        if let body = try SettingsRecord.fetchOne(db, key: "bodyClock") {
            try SettingsRecord(
                section: "bodyClock", value: .encoding(ProfilePreferences.bodyClock(body.value.decode(JSONObject.self)))
            ).save(db)
        }
        try SettingsRecord.deleteOne(db, key: "readiness")
        for var row in try OutboxRecord.fetchAll(db) where row.kind == "settings" {
            var payload = try row.payload.decode(JSONObject.self)
            guard payload["section"] == .string("bodyClock"), let fields = payload["patch"]?.object else { continue }
            var patch = JSONObject(fields)
            if patch["exclude_caffeine"] == nil, let legacy = patch["caffeine_ruled_out"] {
                patch["exclude_caffeine"] = .bool(legacy == .bool(true))
            }
            patch = ProfilePreferences.request(patch)
            if patch.fields.isEmpty {
                try OutboxRecord.deleteOne(db, key: row.id)
            } else {
                payload["patch"] = .object(patch.fields)
                row.payload = try .encoding(payload)
                try row.save(db)
            }
        }
        for var version in try PlanVersionRecord.fetchAll(db)
        where ProfilePreferences.containsRetiredValues(version.detail.rawValue) {
            version.detail = try JSONDocument(data: ProfilePreferences.cleanLegacyJSON(version.detail.data))
            try version.save(db)
        }
        // Recovery tokens may refer to medical answers already sent to the old server.
        for draft in try DraftRecord.fetchAll(db) {
            let documents = [
                draft.form, draft.baseForm, draft.review, draft.wizardReview, draft.wizardState,
                draft.fieldErrors, draft.sourceRevision, draft.saveFailure,
            ]
            if documents.compactMap({ $0 }).contains(where: { ProfilePreferences.containsRetiredValues($0.rawValue) }) {
                try DraftRecord.deleteOne(db, key: draft.id)
            }
        }
    }
}
