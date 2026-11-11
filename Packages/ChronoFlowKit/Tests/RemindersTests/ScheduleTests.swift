import AppCore
import Foundation
import LocalStore
import PlanCore
import Testing

@testable import Reminders

private func scheduled(
    _ plans: [ReminderPlan], now: Date = reminderNow, ledger: [ReminderLedgerEntry] = [],
    settings: ReminderSettings = .init(), language: Language = .en, timeFormat: TimeFormat = .value24
) async throws -> [ReminderRequest] {
    let formatter = try await CopyLineFormatter(catalog: CopyCatalog.load())
    return reminderRequests(
        plans: plans, accountID: reminderAccount, settings: settings, ledger: ledger, now: now, language: language,
        timeFormat: timeFormat, formatter: formatter)
}

@Suite struct ReminderScheduleTests {
    @Test func windowMarginAndCap() async throws {
        let dates = try await scheduled([
            reminderPlan(
                [-1, 0, 24, 48.5, 48.5001].enumerated().map { reminderBlock($0.element, ordinal: $0.offset + 1) })
        ]).map(\.sendAt)
        #expect(dates == [reminderNow.addingTimeInterval(23.5 * 3600), reminderNow.addingTimeInterval(48 * 3600)])
        for milliseconds in [-1, 0, 1, 4999, 5000, 5001] {
            let result = try await scheduled([reminderPlan([reminderBlock(0.5 + Double(milliseconds) / 3_600_000)])])
            #expect(result.count == (milliseconds > 5000 ? 1 : 0))
        }
        let requests = try await scheduled(
            (0..<65).map { reminderPlan([reminderBlock(1 + Double($0) / 100)], id: "trip-\($0)") })
        #expect(requests.count == 60)
        #expect(requests.map(\.sendAt) == requests.map(\.sendAt).sorted())
    }

    @Test func elapsedDailyCapAndDST() async throws {
        for (zone, midnight) in [
            ("UTC", "2026-10-14T00:00:00Z"), ("Pacific/Kiritimati", "2026-10-13T10:00:00Z"),
            ("Pacific/Pago_Pago", "2026-10-14T11:00:00Z"), ("Europe/Amsterdam", "2026-10-24T22:00:00Z"),
        ] {
            let start = planDate(midnight)
            let blocks = (0..<8).map { index -> BlockView in
                var block = reminderBlock(Double(index * 3 + 1), ordinal: index + 1, zone: zone)
                block.startUtc = start.addingTimeInterval(Double(index * 3 + 1) * 3600).ISO8601Format()
                block.endUtc = start.addingTimeInterval(Double(index * 3 + 2) * 3600).ISO8601Format()
                return block
            }
            let first = try await scheduled([reminderPlan(blocks)], now: start)
            #expect(first.count == 6)
            let later = try await scheduled([reminderPlan(blocks)], now: start.addingTimeInterval(8 * 3600))
            #expect(later.map(\.sendAt) == Array(first.dropFirst(3)).map(\.sendAt))
        }
    }

    @Test func ledgerSuppressesMergedMembersAndScopesTripAndHash() async throws {
        let blocks = [reminderBlock(), reminderBlock(1.1, type: .avoidLight)]
        let first = try #require(try await scheduled([reminderPlan(blocks)]).first)
        let ledger = [
            ReminderLedgerEntry(
                tripId: "trip", inputHash: "hash", sendAtMs: first.sendAt.timeIntervalSince1970 * 1000,
                memberKeys: first.memberKeys)
        ]
        let now = first.sendAt.addingTimeInterval(1)
        #expect(try await scheduled([reminderPlan(blocks)], now: now, ledger: ledger).isEmpty)
        #expect(try await scheduled([reminderPlan(blocks, id: "other")], now: now, ledger: ledger).count == 1)
        #expect(try await scheduled([reminderPlan(blocks, hash: "other")], now: now, ledger: ledger).count == 1)
        let futureOnly = try await scheduled([reminderPlan(blocks)], now: now)
        #expect(futureOnly.first?.memberKeys == ["avoid_light|2026-10-14|1"])
    }

    @Test func checksOptionalAndIfYouCan() async throws {
        let blocks = [reminderBlock(), reminderBlock(2, ordinal: 2), reminderBlock(3, ordinal: 3)]
        for status in [CheckStatus.done, .skipped] {
            let mark = CheckMark(key: blocks[1].checkKey!, status: status, markedAt: reminderNow.ISO8601Format())
            let result = try await scheduled([reminderPlan(blocks, marks: [mark])])
            #expect(result.flatMap(\.memberKeys) == ["seek_light|2026-10-14|1", "seek_light|2026-10-14|3"])
        }
        var plan = reminderPlan([reminderBlock(1, type: .avoidLight), reminderBlock(2)])
        plan.detail.timeline.blockReasons = [
            BlockReasonTagsView(blockId: plan.detail.plan.blocks[0].id, lines: [CopyLine(key: "If you can", args: [])])
        ]
        plan.detail.plan.blocks[1].priority = .optional
        #expect(try await scheduled([plan]).isEmpty)
        var completed = reminderPlan()
        completed.card.progress.status = .completed
        #expect(try await scheduled([completed]).isEmpty)
    }

    @Test func copyKindsZonesFormatsLanguagesAndStableIdentity() async throws {
        let blocks = [
            reminderBlock(), reminderBlock(1.1, type: .avoidLight), reminderBlock(1.2, type: .noCaffeine),
            reminderBlock(1.25, type: .sleep, zone: "Europe/Amsterdam"),
        ]
        let en = try #require(try await scheduled([reminderPlan(blocks)]).first)
        #expect(
            en.body
                == "Seek bright light from 01:00. Avoid bright light from 01:06. Last caffeine before 01:12. Wind down for bed: sleep from 03:15 (Amsterdam)."
        )
        let nl = try #require(try await scheduled([reminderPlan(blocks)], language: .nl, timeFormat: .value12).first)
        #expect(
            nl.body
                == "Zoek vanaf 01:00 a.m. fel licht. Vermijd vanaf 01:06 a.m. fel licht. Neem vóór 01:12 a.m. je laatste cafeïne. Kom tot rust: slapen vanaf 03:15 a.m. (Amsterdam)."
        )
        #expect(try await scheduled([reminderPlan(Array(blocks.reversed()))]).first?.body == en.body)
        #expect(en.identifier == nl.identifier)
        #expect(en.title == "Amsterdam → Tokyo")
        for from in ["Amsterdam", nil] as [String?] {
            for to in ["Tokyo", nil] as [String?] {
                var plan = reminderPlan()
                plan.card.from.city = from
                plan.card.to.city = to
                #expect(try await scheduled([plan]).first?.title == "\(from ?? "AMS") → \(to ?? "HND")")
            }
        }
        let duplicateKind = try await scheduled([reminderPlan([reminderBlock(1.1, ordinal: 2), reminderBlock()])])
        #expect(duplicateKind.first?.body == "Seek bright light from 01:00.")
        for (format, time) in [(TimeFormat.value12, "01:30 PM"), (.value24, "13:30")] {
            #expect(
                try await scheduled([reminderPlan([reminderBlock(4.5, zone: "Asia/Tokyo")])], timeFormat: format).first?
                    .body == "Seek bright light from \(time).")
        }
        for (zone, time) in [("Europe/Amsterdam", "03:06 (Amsterdam)"), ("America/Los_Angeles", "18:06 (Los Angeles)")]
        {
            #expect(
                try await scheduled([
                    reminderPlan([reminderBlock(), reminderBlock(1.1, type: .avoidLight, zone: zone)])
                ]).first?.body == "Seek bright light from 01:00. Avoid bright light from \(time).")
        }
    }

    @Test func ledgerValidationAndExpiry() throws {
        for text in ["{", "{}", "[null, {}, {\"memberKeys\": [1]}]"] {
            #expect(ReminderLedger.decode(Data(text.utf8)).isEmpty)
        }
        let valid = ReminderLedgerEntry(
            tripId: "trip", inputHash: "hash", sendAtMs: reminderNow.timeIntervalSince1970 * 1000,
            memberKeys: ["seek_light|2026-10-14|1"])
        #expect(ReminderLedger.decode(try JSONEncoder().encode([valid])) == [valid])
        #expect(ReminderLedger.elapsed([valid], now: reminderNow) == [valid])
        #expect(ReminderLedger.elapsed([valid], now: reminderNow.addingTimeInterval(36 * 3600 + 1)).isEmpty)
        #expect(ReminderLedger.elapsed([valid], now: reminderNow.addingTimeInterval(-1)).isEmpty)
        #expect(
            ReminderLedger.decode(
                Data("[{\"tripId\":\"t\",\"inputHash\":\"h\",\"sendAtMs\":true,\"memberKeys\":[]}]".utf8)
            ).isEmpty)
    }

}
