import AppCore
import Foundation
import PlanCore
import Testing

@testable import PlanUI

extension ModelTests {
    @Test @MainActor func todaySelectionUsesActiveEndThenUpcomingStartAndStableIdentity() throws {
        let detail = try detail()
        let card = recoveryCard(detail)
        let now = planDate(detail.plan.days[0].startUtc)
        func trip(_ id: String, start: Double, end: Double) -> TripListValue {
            var card = card
            card.id = id
            return TripListValue(
                card: card, planStartUtc: now.addingTimeInterval(start).ISO8601Format(),
                planEndUtc: now.addingTimeInterval(end).ISO8601Format(), status: .upcoming)
        }
        let a = trip("a", start: -60, end: 60)
        let b = trip("b", start: -60, end: 120)
        let future = trip("future", start: 240, end: 600)
        #expect(selectTodayTrip([future, b, a], now: now)?.card.id == "a")
        #expect(selectTodayTrip([b, a], now: now.addingTimeInterval(60))?.card.id == "b")
        #expect(selectTodayTrip([a, future], now: now.addingTimeInterval(60))?.card.id == "future")
        #expect(lastEndedTrip([a, b], now: now.addingTimeInterval(180))?.card.id == "b")
    }
    @Test func todaySeparatesCurrentAndFourUpcomingAndDoesNotHideTheNextImportantStep() throws {
        var detail = try detail()
        let now = planDate(detail.plan.days[0].startUtc)
        detail.plan.blocks.sort { $0.startUtc < $1.startUtc }
        let view = todayView(detail, marks: [], now: now)
        #expect(view.upcomingSteps.count <= 4)
        #expect(view.currentSteps.allSatisfy { planDate($0.startUtc) <= now && now < planDate($0.endUtc) })
        #expect(view.currentSteps.allSatisfy { ![BlockType.lightOK, .lightNeutral].contains($0.type) })
        if let next = view.nextStep {
            let hidden = todayView(detail, marks: [], now: now, hidden: [next.type])
            #expect(hidden.nextStep?.id == next.id)
            #expect(!hidden.currentSteps.contains { $0.type == next.type })
            let marked = todayView(
                detail, marks: [CheckMark(key: next.checkKey!, status: .done, markedAt: next.startUtc)], now: now)
            #expect(marked.nextStep?.id != next.id)
        }
    }
    @Test func calendarDaysUseThePlanZoneAcrossDaylightSaving() {
        #expect(
            calendarDaysUntil("2026-03-29T22:30:00Z", now: planDate("2026-03-28T23:30:00Z"), zone: "Europe/Amsterdam")
                == 1)
    }
}
