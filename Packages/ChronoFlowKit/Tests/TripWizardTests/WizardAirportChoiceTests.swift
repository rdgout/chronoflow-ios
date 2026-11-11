import AppCore
import Testing
import TripWizard

@Suite struct WizardAirportChoiceTests {
    @Test(arguments: [false, true]) @MainActor
    func searchAndSelectionRejectAdjacentDuplicatesInBothRoutes(_ home: Bool) async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        var draft = try await store.start()
        draft.form = try WizardForm(input: generationInput())
        if home {
            draft.form.insertStop(wizardAirport("LHR", city: "London", zone: "Europe/London"), beforeDestinationOf: 0)
            draft.form.addReturn()
            draft.form.setRouteAirport(
                wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam"), at: 1, home: true)
        }
        let model = MemberWizardModel(draft: draft, store: store, search: noAirportSearch())
        let start = home ? draft.form.returnBoundary : 0
        let original = try #require(model.draft.form.route(home: home).first?.iata)
        let destination = try #require(model.draft.form.route(home: home).last?.iata)
        let add = WizardAirportSheet(index: start, side: .stop)
        for iata in [original, destination] {
            #expect(!model.airportIsAllowed(iata, sheet: add))
            model.chooseAirport(wizardAirport(iata, city: iata, zone: "UTC"), sheet: add)
            #expect(model.draft == draft)
        }
        let dubai = wizardAirport("DXB", city: "Dubai", zone: "Asia/Dubai")
        let helsinki = wizardAirport("HEL", city: "Helsinki", zone: "Europe/Helsinki")
        model.chooseAirport(dubai, sheet: add)
        let next = WizardAirportSheet(index: start + 1, side: .stop)
        #expect(!model.airportIsAllowed("DXB", sheet: next))
        #expect(!model.airportIsAllowed(destination, sheet: next))
        #expect(model.airportIsAllowed(original, sheet: next))
        model.chooseAirport(helsinki, sheet: next)
        let replace = WizardAirportSheet(index: start, side: .stop, replacingStop: true)
        let before = model.draft
        for iata in [original, "HEL"] {
            #expect(!model.airportIsAllowed(iata, sheet: replace))
            model.chooseAirport(wizardAirport(iata, city: iata, zone: "UTC"), sheet: replace)
            #expect(model.draft == before)
        }
        #expect(model.airportIsAllowed("DXB", sheet: replace))
        #expect(model.airportIsAllowed(destination, sheet: replace))
        let from = WizardAirportSheet(index: start, side: .from)
        let to = WizardAirportSheet(index: start + 2, side: home ? .home : .to)
        #expect(!model.airportIsAllowed("DXB", sheet: from))
        #expect(!model.airportIsAllowed("HEL", sheet: to))
        model.chooseAirport(dubai, sheet: from)
        model.chooseAirport(helsinki, sheet: to)
        #expect(model.draft == before)
        #expect(model.draft.form.routeComplete(home: home))
        try await model.discard()
        try await database.close()
    }

    @Test @MainActor func directRouteStillAllowsTheDesignedSameAirportError() async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        var draft = try await store.start()
        draft.form = try WizardForm(input: generationInput())
        let model = MemberWizardModel(draft: draft, store: store, search: noAirportSearch())
        let sheet = WizardAirportSheet(index: 0, side: .to)
        #expect(model.airportIsAllowed(draft.form.legs[0].fromIata, sheet: sheet))
        model.chooseAirport(wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam"), sheet: sheet)
        #expect(model.draft.form.route().map(\.iata) == ["AMS", "AMS"])
        #expect(!model.whereComplete)
        try await model.discard()
        try await database.close()
    }
}
