import AppCore
import Testing
import TripWizard

@Suite struct WizardHomeRouteTests {
    @Test @MainActor func homeStopChoicesUseTheReturnBoundaryAndDirectPreservesOutbound() async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        var draft = try await store.start()
        draft.form = try WizardForm(input: generationInput())
        draft.form.insertStop(wizardAirport("LHR", city: "London", zone: "Europe/London"), beforeDestinationOf: 0)
        draft.form.addReturn()
        draft.form.setRouteAirport(wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam"), at: 1, home: true)
        draft.form.legs[2].departLocal = "2026-11-20T09:15"
        draft.form.legs[2].arriveLocal = "2026-11-20T19:45"
        draft.state.step = .returnRoute
        let outbound = Array(draft.form.legs.prefix(2))
        let outboundStays = Array(draft.form.stays.prefix(2))
        let homeOrigin = draft.form.legs[2].fromIata
        let model = MemberWizardModel(draft: draft, store: store, search: noAirportSearch())
        model.chooseAirport(
            wizardAirport("DXB", city: "Dubai", zone: "Asia/Dubai"),
            sheet: WizardAirportSheet(index: 2, side: .stop))
        #expect(model.draft.form.route(home: true).map(\.iata) == [homeOrigin, "DXB", "AMS"])
        #expect(model.draft.form.legs[2].departLocal == "2026-11-20T09:15")
        #expect(model.draft.form.legs[2].arriveLocal.isEmpty)
        #expect(model.draft.form.legs[3].departLocal.isEmpty && model.draft.form.legs[3].arriveLocal.isEmpty)
        model.chooseAirport(
            wizardAirport("HEL", city: "Helsinki", zone: "Europe/Helsinki"),
            sheet: WizardAirportSheet(index: 3, side: .stop))
        #expect(model.draft.form.route(home: true).map(\.iata) == [homeOrigin, "DXB", "HEL", "AMS"])
        model.chooseAirport(
            wizardAirport("CDG", city: "Paris", zone: "Europe/Paris"),
            sheet: WizardAirportSheet(index: 3, side: .stop, replacingStop: true))
        #expect(model.draft.form.legs.count == 5 && model.draft.form.returnBoundary == 2)
        #expect(model.draft.form.route(home: true).map(\.iata) == [homeOrigin, "DXB", "CDG", "AMS"])
        #expect(model.draft.form.legs[3].toCity == "Paris" && model.draft.form.legs[4].fromCity == "Paris")
        #expect(Array(model.draft.form.legs.prefix(2)) == outbound)
        #expect(Array(model.draft.form.stays.prefix(2)) == outboundStays)
        model.setDateTime("2026-11-20T19:45", index: 4, arrival: true)
        model.makeDirect(home: true)
        #expect(model.draft.form.route(home: true).map(\.iata) == [homeOrigin, "AMS"])
        #expect(model.draft.form.returnBoundary == 2 && model.draft.form.legs.count == 3)
        #expect(model.draft.form.legs[2].departLocal == "2026-11-20T09:15")
        #expect(model.draft.form.legs[2].arriveLocal == "2026-11-20T19:45")
        #expect(Array(model.draft.form.legs.prefix(2)) == outbound)
        #expect(Array(model.draft.form.stays.prefix(2)) == outboundStays)
        #expect(model.draft.form.stays.count == model.draft.form.legs.count)
        await model.flush()
        #expect(try await store.recover() == model.draft)
        try await model.discard()
        try await database.close()
    }
}
