import AppCore
import Foundation
import GRDB
import LocalStore
import PlanCore

struct ReminderInputs: Sendable, Equatable {
    var settings: [SettingsRecord]
    var trips: [TripRecord]
    var versions: [PlanVersionRecord]
    var checks: [CheckMarkRecord]
    static func fetch(_ db: Database) throws -> Self {
        try Self(
            settings: SettingsRecord.fetchAll(
                db, sql: "SELECT * FROM settings WHERE section IN ('reminders','preferences') ORDER BY section"),
            trips: TripRecord.fetchAll(db, sql: "SELECT * FROM trips ORDER BY id"),
            versions: PlanVersionRecord.fetchAll(db, sql: "SELECT * FROM plan_versions ORDER BY trip_id,input_hash"),
            checks: CheckMarkRecord.fetchAll(
                db, sql: "SELECT * FROM check_marks ORDER BY trip_id,input_hash,type,local_date,ordinal"))
    }
    var plans: [ReminderPlan] {
        trips.compactMap { trip in
            guard trip.keepOffline, trip.deletedAt == nil, !trip.deletedLocally,
                let card = try? trip.card.decode(TripCardView.self), card.progress.status != .completed,
                let version = versions.first(where: { $0.tripId == trip.id && $0.inputHash == trip.currentInputHash }),
                let detail = try? version.decodedDetail()
            else { return nil }
            let marks = checks.filter { $0.tripId == trip.id && $0.inputHash == version.inputHash }.compactMap {
                row -> CheckMark? in
                let status = CheckStatus(rawValue: row.status)
                guard status == .done || status == .skipped else { return nil }
                return CheckMark(
                    key: CheckKeyView(
                        type: BlockType(rawValue: row.type), localDate: row.localDate, ordinal: row.ordinal),
                    status: status, markedAt: row.markedAt)
            }
            return ReminderPlan(card: card, detail: detail, marks: marks)
        }
    }
}

public actor ReminderService {
    public let center: any ReminderNotificationCenter
    private var database: AccountDatabase?
    private var observation: Task<Void, Never>?
    private var flight: Task<Void, Never>?
    private var rerun = false
    private var generation = 0
    private var language: Language = .en
    private var clock: @Sendable () -> Date
    public private(set) var failure: (any Error)?

    public init(center: any ReminderNotificationCenter, now: @escaping @Sendable () -> Date = { Date() }) {
        self.center = center
        clock = now
    }
    public func attach(database: AccountDatabase) async {
        guard self.database !== database else { return }
        await detach()
        self.database = database
        let generation = generation
        observation = Task { [weak self] in
            do {
                var previous: ReminderInputs?
                for try await inputs in try await database.observe(ReminderInputs.fetch) {
                    guard !Task.isCancelled else { return }
                    if previous != inputs {
                        previous = inputs
                        await self?.inputsChanged(generation: generation)
                    }
                }
            } catch {}
        }
    }
    private func inputsChanged(generation: Int) async {
        guard self.generation == generation else { return }
        await reschedule()
    }
    public func setLanguage(_ language: Language) async {
        self.language = language
        await reschedule()
    }
    public func reschedule() async {
        rerun = true
        if let flight {
            await flight.value
            return
        }
        let task = Task { await self.run() }
        flight = task
        await task.value
    }
    private func run() async {
        repeat {
            rerun = false
            let generation = generation
            do { try await schedule(generation: generation) } catch { failure = error }
        } while rerun
        flight = nil
    }
    private func schedule(generation: Int) async throws {
        let pending = await center.pending()
        guard let database, let id = await database.accountID else {
            await center.remove(pending.map(\.identifier))
            return
        }
        let now = clock()
        var ledger = ReminderLedger.elapsed(try await ReminderLedger.read(database: database), now: now)
        let inputs = try await database.read(ReminderInputs.fetch)
        let settings = inputs.settings.first { $0.section == "reminders" }.flatMap {
            try? $0.value.decode(ReminderSettings.self)
        }
        let permission = await center.permission()
        guard self.generation == generation else { return }
        var upcoming: [ReminderRequest] = []
        if let settings, permission.remindersActive(settings) {
            let preferences = inputs.settings.first { $0.section == "preferences" }.flatMap {
                try? $0.value.decode(JSONObject.self)
            }
            let timeFormat = preferences?["timeFormat"]?.string == "12" ? TimeFormat.value12 : .value24
            let formatter = try await CopyLineFormatter(catalog: CopyCatalog.load())
            upcoming = reminderRequests(
                plans: inputs.plans, accountID: id.rawValue, settings: settings, ledger: ledger, now: now,
                language: language, timeFormat: timeFormat, formatter: formatter)
        }
        guard self.generation == generation else { return }
        let desired = Set(upcoming.map(\.identifier))
        await center.remove(pending.filter { !desired.contains($0.identifier) }.map(\.identifier))
        for request in upcoming {
            guard self.generation == generation, !rerun else { break }
            if !pending.contains(request) {
                do { try await center.add(request) } catch { continue }
            }
            ledger.append(
                ReminderLedgerEntry(
                    tripId: request.tripID, inputHash: request.inputHash,
                    sendAtMs: request.sendAt.timeIntervalSince1970 * 1000, memberKeys: request.memberKeys))
        }
        guard self.generation == generation else { return }
        try await ReminderLedger.write(ledger, database: database)
        failure = nil
    }
    public func detach() async {
        generation += 1
        rerun = false
        let previous = observation
        observation = nil
        previous?.cancel()
        let database = database
        self.database = nil
        await flight?.value
        await previous?.value
        await center.remove(await center.pending().map(\.identifier))
        await center.removeDelivered()
        if let database { try? await ReminderLedger.clear(database: database) }
    }
    deinit { observation?.cancel() }
}
