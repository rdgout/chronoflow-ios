import AppCore
import Foundation
import LocalStore
import Testing
import TripWizard

@Suite struct WizardRecoveryTests {
    @Test(arguments: [0.0, 1799.0, 1799.999, 1800.0, 1801.0])
    func recoveryExpiresAtExactlyThirtyMinutes(_ elapsed: TimeInterval) async throws {
        let database = try await wizardDatabase()
        let clock = WizardTestClock()
        let store = MemberWizardStore(database: database, now: { clock.now })
        var draft = try await store.start()
        draft.state.step = .outbound
        draft.state.entered = true
        draft.state.revision = 1
        draft.state.sheet = WizardAirportSheet(index: 0, side: .to)
        draft.form.legs[0].departLocal = "2027-03-28T02:30"
        try await store.persist(draft)
        #expect(try await DraftRepository(database: database).drafts().isEmpty)
        var values = try await DraftRepository(database: database).values().makeAsyncIterator()
        #expect(try await values.next()?.isEmpty == true)
        clock.advance(elapsed)
        let recovered = try await MemberWizardStore(database: database, now: { clock.now }).recover()
        #expect(recovered == (elapsed < 1800 ? draft : nil))
        #expect((try await DraftRepository(database: database).recovery(now: clock.now) == nil) == (elapsed >= 1800))
        try await database.close()
    }

    @Test func firstTripAndLatestOriginPrefillExcludeDeletedTrips() async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        let first = try await store.start()
        #expect(first.state.firstTrip && !first.state.entered && !first.state.fromLastTrip && first.state.sleepNeeded)
        try await store.discard(instance: first.state.instance)
        let trips = TripRepository(database: database)
        try await trips.upsert(wizardTrip(id: "old", origin: "LHR", departure: "2026-09-01T12:00:00Z"))
        try await trips.upsert(wizardTrip(id: "latest", origin: "AMS", departure: "2026-11-01T12:00:00Z"))
        var deleted = try wizardTrip(id: "deleted", origin: "SIN", departure: "2026-12-01T12:00:00Z")
        deleted.deletedAt = "2026-11-01T12:00:00Z"
        try await trips.upsert(deleted)
        deleted.id = "local"
        deleted.deletedAt = nil
        deleted.deletedLocally = true
        try await trips.upsert(deleted)
        try await SettingsRepository(database: database).upsert(
            SettingsRecord(section: "sleepAnswered", value: .encoding(true)))
        let next = try await store.start()
        #expect(!next.state.firstTrip && next.state.fromLastTrip && !next.state.entered && !next.state.sleepNeeded)
        #expect(next.form.legs[0].fromIata == "AMS" && next.form.legs[0].toIata.isEmpty)
        #expect(next.airports["AMS"]?.timezone == "Europe/Amsterdam")
        try await database.close()
    }

    @Test func discardSaveAndExpiredRecordCannotBeResurrectedByAnOldWrite() async throws {
        let database = try await wizardDatabase()
        let clock = WizardTestClock()
        let store = MemberWizardStore(database: database, now: { clock.now })
        var first = try await store.start()
        first.state.revision = 3
        try await store.persist(first)
        var older = first
        older.state.revision = 1
        older.form.legs[0].toIata = "WRONG"
        try await store.persist(older)
        #expect(try await store.recover() == first)
        try await store.discard(instance: first.state.instance)
        await #expect(throws: CancellationError.self) { try await store.persist(first) }
        let second = try await store.start()
        try await store.discard(instance: first.state.instance)
        #expect(try await store.recover() == second)
        try await store.didSave(instance: second.state.instance)
        #expect(try await store.recover() == nil)
        var saved = try await store.start()
        saved.state.savedTripId = "saved"
        try await store.persist(saved)
        #expect(try await store.recover()?.state.savedTripId == "saved")
        try await store.didSave(instance: saved.state.instance)
        let expired = try await store.start()
        clock.advance(1800)
        #expect(try await store.recover() == nil)
        await #expect(throws: CancellationError.self) { try await store.persist(expired) }
        try await database.close()
    }

    @Test @MainActor func editingAndClosingFlushQueuedWritesAndRememberStepAndSheet() async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        let draft = try await store.start()
        let model = MemberWizardModel(draft: draft, store: store, search: noAirportSearch())
        model.openAirport(WizardAirportSheet(index: 0, side: .from))
        model.chooseAirport(
            wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam"),
            sheet: WizardAirportSheet(index: 0, side: .from))
        model.chooseAirport(
            wizardAirport("HND", city: "Tokyo", zone: "Asia/Tokyo"), sheet: WizardAirportSheet(index: 0, side: .to))
        #expect(model.whereComplete && model.draft.state.entered)
        model.go(.outbound)
        model.setDateTime("2027-03-28T02:30", index: 0, arrival: false)
        model.openAirport(WizardAirportSheet(index: 0, side: .stop))
        await model.flush()
        #expect(try await store.recover() == model.draft)
        try await model.discard()
        #expect(try await store.recover() == nil)
        model.setDateTime("2027-03-28T05:30", index: 0, arrival: false)
        await model.flush()
        #expect(try await store.recover() == nil)
        try await database.close()
    }
}

final class WizardTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

func wizardDatabase() async throws -> AccountDatabase {
    let root = URL.temporaryDirectory.appendingPathComponent("WizardTests-\(UUID().uuidString)")
    let database = AccountDatabase(applicationSupport: root, namespace: .mock)
    try await database.open(accountID: "019a562b-8000-7000-8000-000000000001")
    return database
}

func wizardTrip(id: String, origin: String, departure: String) throws -> TripRecord {
    let card = TripCardView(
        id: id, from: AirportRef(iata: origin, city: "Amsterdam", zone: "Europe/Amsterdam"),
        to: AirportRef(iata: "HND", city: "Tokyo", zone: "Asia/Tokyo"),
        departLocal: "2026-11-01T12:00", arriveLocal: "2026-11-02T09:00", departureUtc: departure,
        arrivalUtc: "2026-11-02T00:00:00Z", connections: [], offsetDifferenceMinutes: 480,
        progress: TripProgress(status: .upcoming), canComplete: false, canReopen: false, canEdit: true,
        canDuplicate: true, canDelete: true)
    return TripRecord(id: id, card: try .encoding(card), departureUtc: departure)
}

func noAirportSearch() -> AirportSearchService {
    AirportSearchService(search: { _ in [] }, now: { Date() }, sleep: { _ in })
}
