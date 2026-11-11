import AppCore
import Foundation
import LocalStore
import PlanUI
import Settings
import Sync
import Testing
import TripWizard

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

    @Test(
        arguments: SettingsDevicePreferences.LanguageChoice.allCases,
        [
            "en_US", "en_GB", "nl_NL", "en_US@hours=h23", "nl_NL@hours=h12", "fr_FR@hours=h12",
        ])
    func appLanguagePreservesThePhonesHourOverrideForPillsAndPickers(
        _ language: SettingsDevicePreferences.LanguageChoice, _ phoneIdentifier: String
    ) throws {
        let name = "SettingsClockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = SettingsDevicePreferences(defaults: defaults)
        model.language = language
        let phone = Locale(identifier: phoneIdentifier)
        let locale = model.resolvedLocale(phone: phone)
        let expectedLanguage = language == .system ? (phoneIdentifier.hasPrefix("nl") ? "nl" : "en") : language.rawValue
        #expect(locale.language.languageCode?.identifier == expectedLanguage)
        #expect(locale.hourCycle == phone.hourCycle)
        let format = try #require(DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale))
        let pill = try #require(WizardDateTime.formatLocal("2027-03-28T14:40", locale: locale))
        if phone.hourCycle == .oneToTwelve {
            #expect(format.contains("h") && format.contains("a"))
            #expect(pill.contains("2:40") && !pill.contains("14:40"))
        } else {
            #expect(format.contains("H") && !format.contains("a"))
            #expect(pill.contains("14:40"))
        }
        #expect(pill.lowercased().contains(expectedLanguage == "nl" ? "mrt" : "mar"))
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

    @Test(arguments: [true, false])
    func replayTwiceStartsFreshAfterSkipOrDone(skip: Bool) async throws {
        var writes: [JSONObject] = []
        let preferences = SettingsPreferencesModel(value: JSONObject(["timeFormat": .string("24")])) {
            writes.append($0)
        }
        await preferences.setTimeFormat("12")
        preferences.startWalkthroughReplay()
        let first = try #require(preferences.walkthrough)
        if skip {
            await first.skip()
        } else {
            await first.advance()
            await first.advance()
            await first.advance()
        }
        #expect(first.completed && preferences.walkthrough == nil)

        preferences.startWalkthroughReplay()
        let second = try #require(preferences.walkthrough)
        #expect(second !== first && second.mode == .replay)
        #expect(second.page == .timeline && !second.completed && !second.busy && second.failure == nil)
        await second.advance()
        #expect(second.page == .categories && !second.completed)
        await second.advance()
        #expect(second.page == .progress && !second.completed)
        await second.advance()
        #expect(second.completed && preferences.walkthrough == nil)
        #expect(preferences.value["timeFormat"] == .string("12") && preferences.saved)
        #expect(writes == [JSONObject(["time_format": .string("12")])])
    }
}
