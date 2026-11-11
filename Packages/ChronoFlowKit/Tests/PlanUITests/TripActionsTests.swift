import AppCore
import DataAccess
import Foundation
import Testing

@testable import PlanUI

struct TripActionsTests {
    @Test func flagsConnectionAndBusyGateBothActionsIndependently() {
        for edit in [false, true] {
            for duplicate in [false, true] {
                for online in [false, true] {
                    for busy in [false, true] {
                        let value = TripActionsAvailability(
                            canEdit: edit, canDuplicate: duplicate, online: online, busy: busy)
                        #expect(value.enabled(.edit) == (edit && online && !busy))
                        #expect(value.enabled(.duplicate) == (duplicate && online && !busy))
                    }
                }
            }
        }
    }

    @Test func headerIncludesDatesConnectionsAndReturnWithPairedCopy() throws {
        let account = try MockAppSeed.make(now: Date(timeIntervalSince1970: 1_794_096_000)).accounts.values.first!
        var card = account.trips[0].card
        var detail = account.details[card.id]!
        card.connections = [card.to]
        detail.trip.legs[0].returnLeg = true
        for language in [Language.en, .nl] {
            let header = TripActionsHeader(card: card, detail: detail, language: language)
            #expect(header.title == "\(card.from.city ?? card.from.iata) → \(card.to.city ?? card.to.iata)")
            #expect(header.subtitle.contains(" · via \(card.to.city ?? card.to.iata) · "))
            #expect(header.subtitle.hasSuffix(language == .nl ? "met terugreis" : "with return"))
            let copy = PageCopy(language: language)
            #expect(copy("Edit trip") == (language == .nl ? "Reis bewerken" : "Edit trip"))
            #expect(copy("Needs a connection.") == (language == .nl ? "Verbinding nodig." : "Needs a connection."))
        }
        let withoutPlan = TripActionsHeader(card: card, detail: nil, language: .en)
        #expect(!withoutPlan.subtitle.contains("with return"))
        #expect(withoutPlan.subtitle.hasPrefix(tripDatesText(start: card.departLocal, end: nil, language: .en)))
    }
}
