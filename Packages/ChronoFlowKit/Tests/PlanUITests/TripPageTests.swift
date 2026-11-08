import AppCore
import Foundation
import PlanCore
import Testing

@testable import PlanUI

struct TripPageTests {
    @Test func stateGatingTable() {
        for keep in [false, true] {
            for stored in [false, true] {
                for online in [false, true] {
                    for awaiting in [false, true] {
                        for fetch in [TripPageFetch.idle, .loading, .loaded, .failed, .notFound] {
                            let result = TripPageState.resolve(
                                keepOffline: keep, stored: stored, online: online, fetch: fetch, awaitingSync: awaiting)
                            if stored {
                                #expect(result == .ready)
                            } else if awaiting || keep {
                                #expect(result == .loading)
                            } else if !online {
                                #expect(result == .remoteOffline)
                            } else if case .failed = fetch {
                                #expect(result == .server)
                            } else if case .notFound = fetch {
                                #expect(result == .notFound)
                            } else {
                                #expect(result == .remoteLoading)
                            }
                        }
                    }
                }
            }
        }
        #expect(
            TripPageState.resolve(keepOffline: true, stored: true, noPlan: true, online: false, fetch: .failed)
                == .noPlan)
        #expect(
            TripPageState.resolve(keepOffline: true, stored: true, online: false, fetch: .idle, tombstoned: true)
                == .notFound)
        #expect(
            TripPageState.resolve(
                keepOffline: false, stored: false, online: false, fetch: .idle, missingAfterSync: true) == .notFound)
        #expect(
            TripPageState.resolve(
                keepOffline: false, stored: false, online: true, fetch: .idle, missingAfterSync: true,
                awaitingSync: true) == .loading)
    }

    @Test func openingOrderAndReplacement() throws {
        let detail = try fixtureDetail()
        let days = detail.plan.days
        let today = planDate(days[2].startUtc)
        func open(day: String? = nil, block: String? = nil, kept: String? = nil, now: Date? = nil) -> DayView? {
            openingDay(
                days, blocks: detail.plan.blocks, requestedDay: day, blockID: block, keptDay: kept, now: now ?? today)
        }
        #expect(open(day: days[0].id, kept: days[1].id)?.id == days[0].id)
        let block = try #require(
            detail.plan.blocks.first {
                planDate($0.startUtc) >= today && planDate($0.startUtc) < planDate(days[2].endUtc)
            })
        #expect(open(block: block.id, kept: days[0].id)?.id == days[2].id)
        #expect(open(kept: days[1].id)?.id == days[1].id)
        #expect(open()?.id == days[2].id)
        #expect(open(now: planDate(days.last!.endUtc))?.id == days.last?.id)
        #expect(open(now: planDate(days[0].startUtc) - 60)?.id == days[0].id)
        var new = days
        new[2].id = "replacement"
        let anchor = TripPageAnchor(dayID: days[2].id, labelDate: days[2].labelDate, offset: 180)
        #expect(replacementAnchor(anchor, days: new).dayID == "replacement")
        #expect(replacementAnchor(anchor, days: new).offset == 180)
        #expect(replacementAnchor(anchor, days: Array(new.suffix(1))).dayID == new.last?.id)
    }

    @Test func preparationCachesLayoutsAndPreservesMarkLabels() async throws {
        let detail = try fixtureDetail()
        let decoder = PlanDecoder()
        let first = try await decoder.prepare(detail, hidden: [], language: .en, timeFormat: .value24, marks: [])
        _ = try await decoder.prepare(detail, hidden: [], language: .en, timeFormat: .value24, marks: [])
        #expect(await decoder.layoutCount == 1)
        let block = try #require(
            detail.plan.blocks.first { $0.actionable && $0.checkKey != nil && !isOptionalStep($0) })
        let mark = CheckMark(key: block.checkKey!, status: .done, markedAt: detail.plan.days[0].startUtc)
        let changed = try await decoder.prepare(detail, hidden: [], language: .nl, timeFormat: .value12, marks: [mark])
        #expect(await decoder.layoutCount == 1)
        #expect(first.days.count == changed.days.count)
        #expect(changed.days.flatMap(\.blocks).first { $0.id == block.id }?.status == .done)
        #expect(PageCopy(language: .nl)("Go to day") == "Ga naar dag")
        await decoder.evict(tripID: detail.trip.id)
        _ = try await decoder.prepare(detail, hidden: [], language: .en, timeFormat: .value24, marks: [])
        #expect(await decoder.layoutCount == 2)
    }
}

private func fixtureDetail() throws -> TripDetail {
    try JSONDecoder().decode(
        TripDetail.self,
        from: Data(
            contentsOf: Bundle.module.url(forResource: "detail", withExtension: "json", subdirectory: "Fixtures")!))
}
