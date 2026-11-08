import AppCore
import DataAccess
import Foundation
import PlanCore
import Testing

@testable import PlanUI

struct TripPageCopyTests {
    @Test func warningAndNotePluralsFollowTheSelectedLanguage() {
        for (language, warning, warnings, note, notes) in [
            (Language.en, "warning", "warnings", "note", "notes"),
            (.nl, "waarschuwing", "waarschuwingen", "notitie", "notities"),
        ] {
            let copy = PageCopy(language: language)
            #expect(copy.count("%lld warnings", 1) == "1 " + warning)
            #expect(copy.count("%lld notes", 1) == "1 " + note)
            for count in [0, 2, 12] {
                #expect(copy.count("%lld warnings", count) == "\(count) " + warnings)
                #expect(copy.count("%lld notes", count) == "\(count) " + notes)
            }
        }
    }

    @Test func compactDateRangesAndOutboundFlightNumbers() async throws {
        #expect(tripDatesText(start: "2026-10-12", end: "2026-10-18", language: .en) == "12–18 Oct")
        #expect(tripDatesText(start: "2026-10-12", end: "2026-10-12", language: .en) == "12 Oct")
        #expect(tripDatesText(start: "2026-10-12", end: "2026-11-02", language: .en) == "12 Oct–2 Nov")
        #expect(tripDatesText(start: "2026-12-30", end: "2027-01-02", language: .en) == "30 Dec 2026–2 Jan 2027")
        #expect(tripDatesText(start: "2026-10-12", end: "2026-10-18", language: .en, long: true) == "12 to 18 October")
        #expect(tripDatesText(start: "2026-10-12", end: "2026-10-18", language: .nl, long: true) == "12 tot 18 oktober")
        var detail = try MockTimelineFixtures.fixture(named: "S3").detail
        detail.trip.legs = [
            .init(position: 0, flightNumber: " KL 861 ", from: detail.trip.from, to: detail.trip.to, returnLeg: false),
            .init(position: 1, flightNumber: "", from: detail.trip.from, to: detail.trip.to, returnLeg: false),
            .init(position: 2, flightNumber: "JL 1", from: detail.trip.from, to: detail.trip.to, returnLeg: false),
            .init(position: 3, flightNumber: "RETURN", from: detail.trip.to, to: detail.trip.from, returnLeg: true),
        ]
        let prepared = preparePlan(
            detail, layouts: layoutPlan(detail.plan, timeline: detail.timeline),
            formatter: CopyLineFormatter(catalog: try await CopyCatalog.load()), language: .en)
        #expect(prepared.subtitle.hasSuffix(" · KL 861 · JL 1"))
        #expect(!prepared.subtitle.contains("RETURN"))
        let copy = PageCopy(language: .nl)
        #expect(copy("Home · %@", "Amsterdam") == "Thuis · Amsterdam")
        #expect(copy("There · %@", "Tokyo") == "Daar · Tokyo")
        #expect(copy("%@ · now", "10:30 AM") == "10:30 AM · nu")
        #expect(
            copy("%@ to %@, %@, %@. Go to a day", "Amsterdam", "Tokyo", "Reisdag", "ma 12 okt")
                == "Amsterdam naar Tokyo, Reisdag, ma 12 okt. Ga naar een dag")
    }

    @Test func preparationPreservesNoticeTones() async throws {
        let detail = try MockTimelineFixtures.fixture(named: "S3").detail
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        let layouts = layoutPlan(detail.plan, timeline: detail.timeline)
        for language in [Language.en, .nl] {
            let prepared = preparePlan(detail, layouts: layouts, formatter: formatter, language: language)
            for day in prepared.days {
                let notices = noticeItems(detail.plan, notices: detail.notices, day: day.day)
                #expect(day.notices.map(\.warning) == notices.map(\.warning))
                #expect(day.warningCount == day.notices.filter(\.warning).count)
                #expect(day.notices.allSatisfy { !$0.text.isEmpty })
                #expect(day.shownNotices(expanded: false, notesOpen: true).isEmpty)
                #expect(day.shownNotices(expanded: true, notesOpen: true) == day.notices)
                #expect(day.shownNotices(expanded: true, notesOpen: false) == (day.warningCount > 0 ? day.notices : []))
            }
        }
    }
}
