import AppCore
import Foundation
import LocalStore
import Settings
import Sync
import Testing

@testable import DataAccess

@Suite @MainActor struct SettingsBodyClockTests {
    @Test func reopenedEditorUsesChronotypeObservedFromLocalSave() async throws {
        let f = try await SettingsPageFixture.make()
        try await f.database.write { db in
            try StoreApplication.setting(
                "bodyClock", value: .encoding(JSONObject(["chronotype": .string("early")])), db: db)
        }
        let pages = f.model()
        pages.start()
        defer { pages.stop() }
        try await f.waitUntil { pages.settingsLoaded && pages.settings["bodyClock"]?["chronotype"] == .string("early") }
        let editor = SettingsBodyClockModel(answers: try #require(pages.settings["bodyClock"])) { patch in
            try await pages.enqueue(.settings(section: .bodyClock, patch: patch))
        }
        await editor.change(.about, ["chronotype": .string("late")])
        #expect(editor.saved.contains(.about))
        try await f.waitUntil { pages.settings["bodyClock"]?["chronotype"] == .string("late") }
        let reopened = SettingsBodyClockModel(answers: try #require(pages.settings["bodyClock"])) { _ in
            Issue.record("Reopening must not save")
        }
        #expect(reopened.answers["chronotype"] == .string("late"))
        #expect(reopened.saved.isEmpty && !pages.failure)
        pages.stop()
        try await f.close()
    }

    @Test func chronotypeSelectionIsSavedLocallyAndQueuedBeforeShowingSaved() async throws {
        let f = try await SettingsPageFixture.make()
        let model = SettingsBodyClockModel(answers: JSONObject(["ageBand": .string("18_64")])) { patch in
            try await f.model().enqueue(.settings(section: .bodyClock, patch: patch))
        }
        await model.change(.about, ["chronotype": .string("late")])
        #expect(model.saved == [.about] && !model.failure && model.errors.isEmpty)
        try await f.database.close()
        try await f.database.open(accountID: f.id)
        let rows = try await SettingsRepository(database: f.database).settings()
        let body = try #require(try rows.first { $0.section == "bodyClock" }?.value.decode(JSONObject.self))
        #expect(body["chronotype"] == .string("late"))
        #expect(body["ageBand"] == .string("18_64"))
        let pending = try await OutboxRepository(database: f.database).pending()
        #expect(pending.count == 1 && pending.first?.kind == "settings")
        let payload = try #require(try pending.first?.payload.decode(JSONObject.self))
        #expect(payload["section"] == .string("bodyClock"))
        #expect(payload["patch"]?.object?["chronotype"] == .string("late"))
        try await f.close()
    }

    @Test func invalidSleepStaysInDraftAndDoesNotReachOutboxUntilBothTimesAreValid() async {
        var writes: [JSONObject] = []
        let stored = JSONObject([
            "habitualBed": .string("23:00"), "habitualWake": .string("07:00"), "ageBand": .string("18_64"),
        ])
        let model = SettingsBodyClockModel(answers: stored) { writes.append($0) }
        await model.change(.sleep, ["habitualWake": .string("23:30")])
        #expect(writes.isEmpty && model.errors["habitualWake"] != nil)
        model.receive(stored)
        #expect(model.answers["habitualWake"] == .string("23:30"))
        await model.change(.sleep, ["habitualBed": .string("15:00")])
        #expect(writes.count == 1)
        #expect(writes[0]["habitual_bed"] == .string("15:00"))
        #expect(writes[0]["habitual_wake"] == .string("23:30"))
        #expect(writes[0]["free_day_bed"] == .null)
        #expect(model.answers["ageBand"] == .string("18_64"))
    }

    @Test func normalizesDependentValuesAndValidatesCupsAndRating() async {
        var writes: [JSONObject] = []
        let model = SettingsBodyClockModel(answers: JSONObject()) { writes.append($0) }
        await model.change(.caffeine, ["caffeineHabit": .string("cups")])
        #expect(model.errors["cupsFilterCoffee"] != nil && writes.isEmpty)
        await model.change(.caffeine, ["cupsFilterCoffee": .number(2)])
        #expect(model.errors.isEmpty && writes.count == 1)
        await model.change(.caffeine, ["cupsTea": .number(21)])
        #expect(model.errors["cupsFilterCoffee"] != nil && writes.count == 1)
        await model.change(.caffeine, ["caffeineHabit": .string("non_user")])
        #expect(writes.last?["cups_filter_coffee"] == .null)
        await model.change(.light, ["blueBlockers": .string("rated"), "blueBlockerMdfd": .string("10")])
        #expect(model.errors["blueBlockerMdfd"] != nil)
        await model.change(.light, ["blueBlockerMdfd": .string("2.1")])
        #expect(writes.last?["blue_blocker_mdfd"] == .string("2.1"))
        await model.change(.light, ["blueBlockers": .string("no")])
        #expect(writes.last?["blue_blocker_mdfd"] == .null)
    }

    @Test func failedLocalSaveRetainsAnswerAndAllowsRetry() async {
        var failing = true
        let model = SettingsBodyClockModel(answers: JSONObject()) { _ in
            if failing { throw StoreFailure.closed }
        }
        await model.change(.about, ["ageBand": .string("65_plus")])
        #expect(model.failure && !model.saved.contains(.about))
        #expect(model.answers["ageBand"] == .string("65_plus"))
        failing = false
        await model.change(.about, [:])
        #expect(!model.failure && model.saved.contains(.about))
    }

    @Test func offlineQueueAndPullsPreservePendingValuesInOtherGroups() async throws {
        let f = try await SettingsPageFixture.make()
        let model = SettingsBodyClockModel(answers: JSONObject(["ageBand": .string("18_64")])) { patch in
            try await OutboxRepository(database: f.database).enqueue(
                .settings(section: .bodyClock, patch: patch), permit: f.permit)
        }
        await model.change(.about, ["ageBand": .string("65_plus")])
        await model.change(.sleep, ["habitualBed": .string("23:15"), "habitualWake": .string("07:45")])
        let epoch = SyncEpoch(accountID: try AccountID(f.id), generation: 0)
        #expect(
            try await OutboxFlusher(database: f.database, source: MockDataSource(offline: true)).run(epoch: epoch)
                .offline)
        try await f.database.write { db in
            try StoreApplication.setting(
                "bodyClock", value: .encoding(JSONObject(["ageBand": .string("18_64")])), db: db)
        }
        let rows = try await SettingsRepository(database: f.database).settings()
        let body = try #require(try rows.first { $0.section == "bodyClock" }?.value.decode(JSONObject.self))
        #expect(body["ageBand"] == .string("65_plus"))
        #expect(body["habitualBed"] == .string("23:15"))
        #expect(try rows.first { $0.section == "sleepAnswered" }?.value.decode(Bool.self) == true)
        #expect(try await OutboxRepository(database: f.database).pending().count == 2)
        try await f.close()
    }

    @Test func completionOfAnOlderSaveDoesNotMarkANewerInvalidDraftAsSaved() async {
        let began = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let model = SettingsBodyClockModel(answers: JSONObject()) { _ in
            began.continuation.yield()
            for await _ in release.stream { break }
        }
        let first = Task {
            await model.change(.sleep, ["habitualBed": .string("23:00"), "habitualWake": .string("07:00")])
        }
        var iterator = began.stream.makeAsyncIterator()
        _ = await iterator.next()
        await model.change(.sleep, ["habitualWake": .string("23:30")])
        release.continuation.yield()
        await first.value
        #expect(!model.saved.contains(.sleep) && model.errors["habitualWake"] != nil)
        #expect(model.answers["habitualWake"] == .string("23:30"))
        began.continuation.finish()
        release.continuation.finish()
    }

    @Test func sleepDurationChecksClockBoundsAndCrossesMidnight() {
        #expect(SettingsBodyClockModel.sleepMinutes(bed: "23:00", wake: "07:00") == 480)
        #expect(SettingsBodyClockModel.sleepMinutes(bed: "24:00", wake: "07:00") == nil)
        #expect(SettingsBodyClockModel.sleepMinutes(bed: "1:00", wake: "07:00") == nil)
    }
}
