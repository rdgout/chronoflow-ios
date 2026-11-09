import AppCore
import Foundation
import LocalStore
import Settings
import Testing

@Suite struct SettingsHomeStateTests {
    private let now = Date(timeIntervalSince1970: 1_794_132_000)
    private func state(age: TimeInterval) -> SettingsHomeState {
        SettingsHomeState(
            account: AccountRecord(
                id: "account", name: "  Rick van Gout  ", email: "r@example.test",
                syncedAt: now.addingTimeInterval(-age).ISO8601Format()))
    }

    @Test func syncedLineAgeAndPriorityMatchRN() {
        for (age, key, count) in [
            (0.0, "Synced just now", nil), (-60, "Synced just now", nil),
            (59, "Synced just now", nil), (60, "Synced %lld min ago", 1),
            (3599, "Synced %lld min ago", 59), (3600, "Synced %lld hours ago", 1),
            (86399, "Synced %lld hours ago", 23), (86400, "Synced yesterday", nil),
            (172800, "Synced %lld days ago", 2), (604800, "Synced on {{date}}", nil),
        ] as [(Double, String, Int?)] {
            #expect(state(age: age).syncCopy(now: now, zone: .gmt)?.key == key)
            #expect(state(age: age).syncCopy(now: now, zone: .gmt)?.count == count)
        }
        var value = state(age: 120)
        #expect(value.syncCopy(now: now, offline: true)?.key == "Saved on this phone · syncs when you're online")
        value.pendingCount = 2
        #expect(value.syncCopy(now: now, offline: true)?.count == 2)
        #expect(value.syncCopy(now: now, syncing: true, offline: true)?.key == "Syncing…")
        value.pendingCount = 0
        value.account?.syncedAt = "invalid"
        #expect(value.syncCopy(now: now) == nil)
        #expect(SettingsHomeState().syncCopy(now: now) == nil)
    }

    @Test func initialsReadinessAndCreditsFollowLocalValues() throws {
        var value = state(age: 0)
        #expect(value.initials == "RG")
        value.account?.name = "éva"
        #expect(value.initials == "É")
        value.account?.name = "🧑🏽‍💻 de Vries"
        #expect(value.initials == "🧑🏽‍💻V")
        value.account?.name = "  "
        #expect(value.initials.isEmpty)
        let readiness = try SettingsRecord(
            section: "readiness",
            value: JSONDocument(
                """
                {"variant":"needs-answers","missing":["age","shift"],"invalidSections":["sleep"]}
                """))
        let credits = try SettingsRecord(
            section: "planCredits", value: JSONDocument("{\"credits\":2,\"unlimited\":false}"))
        value.apply(settings: [readiness, credits])
        #expect(value.missingAnswers == 3)
        #expect(value.credits == 2)
        value.apply(settings: [
            try SettingsRecord(section: "planCredits", value: JSONDocument("{\"credits\":2,\"unlimited\":true}"))
        ])
        #expect(value.missingAnswers == 0)
        #expect(value.credits == nil)
        value.apply(settings: [try SettingsRecord(section: "planCredits", value: JSONDocument("{\"credits\":0}"))])
        #expect(value.credits == 0)
        value.apply(settings: [])
        #expect(value.credits == nil)
    }

    @Test @MainActor func pendingChangesGroupSettingsAndUseLatestCheckAcrossHashes() throws {
        func check(_ id: String, _ status: CheckStatus?, hash: String = "old") throws -> OutboxRecord {
            try OutboxRecord(
                id: id, kind: "check-off",
                payload: .encoding(
                    CheckOffChange(
                        tripID: "trip", planInputHash: hash, type: .avoidLight, localDate: "2026-11-08", ordinal: 1,
                        status: status)), createdAt: id)
        }
        func setting(_ id: String, _ section: String) throws -> OutboxRecord {
            try OutboxRecord(
                id: id, kind: "settings",
                payload: JSONDocument("{\"section\":\"\(section)\",\"patch\":{\"habitual_bed\":\"23:00\"}}"),
                createdAt: id)
        }
        let value = SettingsHomeState(outbox: [
            try check("1", .done), try setting("2", "bodyClock"), try setting("3", "bodyClock"),
            try check("4", .done, hash: "new"), try setting("5", "preferences"),
        ])
        #expect(value.pendingCount == 5)
        #expect(value.pending.map(\.id) == ["4", "2", "5"])
        #expect(value.pending[0].text(language: .en) == "Checked off \"Avoid bright light\"")
        #expect(value.pending[0].text(language: .nl) == "\"Vermijd fel licht\" afgevinkt")
        #expect(value.pending[1].category == .sleep)
        #expect(value.pending[1].text(language: .nl) == "Je gebruikelijke slaaptijden aangepast")
        #expect(value.pending[2].copy.key == "A change waiting to sync")
        let undone = SettingsHomeState(outbox: [try check("1", .done), try check("2", nil)])
        #expect(undone.pending.count == 1)
        #expect(undone.pending[0].copy.key == "A change waiting to sync")
    }
}
