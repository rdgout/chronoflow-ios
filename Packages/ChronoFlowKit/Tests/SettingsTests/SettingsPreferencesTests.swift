import AppCore
import Foundation
import LocalStore
import PlanUI
import Settings
import Sync
import Testing

@testable import DataAccess

@Suite @MainActor struct SettingsPreferencesTests {
    @Test func groupsPreserveUnrelatedAndFutureCategoriesAndOnlySendChangedSetting() async {
        var writes: [JSONObject] = []
        let model = SettingsPreferencesModel(
            value: JSONObject([
                "timeFormat": .string("24"),
                "hiddenCategories": .array([.string("flight"), .string("future_category")]),
            ])
        ) { writes.append($0) }
        await model.setShown(false, group: SettingsTimelineGroup.all[0])
        #expect(model.hidden == ["flight", "future_category", "sleep", "nap", "rest"])
        #expect(writes.last?.fields.keys.sorted() == ["hidden_categories"])
        await model.setShown(true, group: SettingsTimelineGroup.all[0])
        #expect(model.hidden == ["flight", "future_category"])
        await model.setTimeFormat("12")
        #expect(writes.last == JSONObject(["time_format": .string("12")]))
        #expect(model.hidden == ["flight", "future_category"])
        let count = writes.count
        await model.setTimeFormat("13")
        #expect(model.failure && writes.count == count)
    }

    @Test func localFailureKeepsDraftThroughIncomingValuesAndCanRetry() async {
        var failing = true
        let model = SettingsPreferencesModel(value: JSONObject(["timeFormat": .string("24")])) { _ in
            if failing { throw StoreFailure.closed }
        }
        await model.setTimeFormat("12")
        model.receive(JSONObject(["timeFormat": .string("24")]))
        #expect(model.value["timeFormat"] == .string("12") && model.failure)
        failing = false
        await model.setTimeFormat("12")
        #expect(model.saved && !model.failure)
    }

    @Test func offlineChangesRemainPendingDuringPull() async throws {
        let f = try await SettingsPageFixture.make()
        let model = SettingsPreferencesModel(value: JSONObject(["timeFormat": .string("24")])) { patch in
            try await OutboxRepository(database: f.database).enqueue(
                .settings(section: .preferences, patch: patch), permit: f.permit)
        }
        await model.setTimeFormat("12")
        let epoch = SyncEpoch(accountID: try AccountID(f.id), generation: 0)
        #expect(
            try await OutboxFlusher(database: f.database, source: MockDataSource(offline: true)).run(epoch: epoch)
                .offline)
        try await f.database.write { db in
            try StoreApplication.setting(
                "preferences", value: .encoding(JSONObject(["timeFormat": .string("24")])), db: db)
        }
        let rows = try await SettingsRepository(database: f.database).settings()
        #expect(
            try rows.first { $0.section == "preferences" }?.value.decode(JSONObject.self)["timeFormat"] == .string("12")
        )
        try await f.close()
    }

    @Test func localLanguageAndThemePersistAndUnsupportedPhoneLanguageFallsBackToEnglish() throws {
        let name = "SettingsPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = SettingsDevicePreferences(defaults: defaults)
        #expect(model.theme == .system && model.language == .system)
        #expect(model.resolvedLocale(phone: Locale(identifier: "nl_NL")).language.languageCode?.identifier == "nl")
        #expect(model.resolvedLocale(phone: Locale(identifier: "fr_FR")).language.languageCode?.identifier == "en")
        model.theme = .dark
        model.language = .nl
        let restored = SettingsDevicePreferences(defaults: defaults)
        #expect(restored.theme == .dark && restored.language == .nl)
        #expect(restored.resolvedLocale(phone: Locale(identifier: "en_US")).language.languageCode?.identifier == "nl")
    }

    @Test func replaySkipAndDoneReturnToPreferencesWithoutAnotherCompletionWrite() async {
        for skip in [true, false] {
            var presented = true
            var writes = 0
            let model = WalkthroughModel(mode: .replay, complete: { writes += 1 }, onFinish: { presented = false })
            if skip {
                await model.skip()
            } else {
                await model.advance()
                await model.advance()
                await model.advance()
            }
            #expect(!presented && model.completed && writes == 0)
        }
    }
}
