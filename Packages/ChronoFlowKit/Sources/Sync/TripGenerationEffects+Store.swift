import AppCore
import Foundation
import LocalStore
import TripWizard

extension TripGenerationEffects {
    public static func storing(
        database: AccountDatabase, source: any DataSource, epoch: SyncEpoch, permit: SessionMutationPermit? = nil,
        requestSync: @escaping @Sendable () async -> Void, now: @escaping @Sendable () -> Date = { Date() }
    ) -> Self {
        Self(
            mergeProfile: { patch in
                let epoch = epoch.child()
                try await database.validate(epoch: epoch)
                try await database.write(epoch: epoch, permit: permit) { db in
                    var body =
                        try SettingsRecord.fetchOne(db, key: "bodyClock")?.value.decode(JSONObject.self) ?? JSONObject()
                    func merge(_ patch: JSONObject) {
                        for (key, value) in patch.fields {
                            let parts = key.split(separator: "_")
                            let camel =
                                String(parts[0])
                                + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
                            body[camel] = value
                        }
                    }
                    merge(patch)
                    for row in try StoreApplication.pending(db) {
                        if case .settings(.bodyClock, let pending) = try row.change { merge(pending) }
                    }
                    try SettingsRecord(section: "bodyClock", value: .encoding(body)).save(db)
                    try SettingsRecord.deleteOne(db, key: "readiness")
                    let sleepFields: Set<String> = [
                        "habitual_bed", "habitual_wake", "free_day_status", "free_day_bed", "free_day_wake",
                        "chronotype",
                    ]
                    if !Set(patch.fields.keys).isDisjoint(with: sleepFields) {
                        try SettingsRecord(section: "sleepAnswered", value: .encoding(true)).save(db)
                    }
                }
            },
            pullCreatedTrip: { tripID in
                let epoch = epoch.child()
                try await database.validate(epoch: epoch)
                let trips = try await source.fetchTrips()
                try epoch.check()
                let at = now().ISO8601Format()
                try await database.write(epoch: epoch, permit: permit) { db in
                    try TripRepository.applyCards(trips, at: at, db: db)
                }
                let detail = try await source.fetchTripDetail(id: tripID)
                try epoch.check()
                try await database.write(epoch: epoch, permit: permit) { db in
                    try TripRepository.applyDetail(detail, tripID: tripID, at: at, db: db)
                }
            },
            requestSync: {
                guard (try? epoch.check()) != nil else { return }
                await requestSync()
            })
    }
}
