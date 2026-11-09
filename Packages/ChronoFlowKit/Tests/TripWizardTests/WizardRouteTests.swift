import AppCore
import Foundation
import LocalStore
import Testing
import TripWizard

@Suite struct WizardRouteTests {
    let stop = wizardAirport("DXB", city: "Dubai", zone: "Asia/Dubai")
    let second = wizardAirport("HEL", city: "Helsinki", zone: "Europe/Helsinki")

    @Test @MainActor func returnChoiceStartsWithADirectRouteAndEmptyTimes() async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        var draft = try await store.start()
        draft.form = try WizardForm(input: generationInput())
        draft.form.insertStop(stop, beforeDestinationOf: 0)
        draft.form.insertStop(second, beforeDestinationOf: 1)
        draft.state.step = .returnChoice
        let clock = CheckingTestClock()
        let model = MemberWizardModel(draft: draft, store: store, search: noAirportSearch(), checkingClock: clock.clock)
        model.chooseReturn("return_legs")
        try await eventually { clock.deadlines.contains(0.25) }
        clock.advance(to: 0.25)
        try await eventually { model.draft.state.step == .returnRoute }
        #expect(
            model.draft.form.route(home: true).map(\.iata) == [
                draft.form.legs.last!.toIata, draft.form.legs[0].fromIata,
            ])
        #expect(model.draft.form.legs.count == 4)
        #expect(model.draft.form.legs.last?.departLocal.isEmpty == true)
        #expect(model.draft.form.legs.last?.arriveLocal.isEmpty == true)
        #expect(model.draft.state.returnRouteConfirmed == false)
        model.finishReturnRoute()
        #expect(model.draft.state.step == .returnFlight)
        model.openAirport(WizardAirportSheet(index: 0, side: .stop, replacingStop: true))
        model.chooseAirport(
            wizardAirport("LHR", city: "London", zone: "Europe/London"),
            sheet: WizardAirportSheet(index: 0, side: .stop, replacingStop: true))
        #expect(model.draft.form.legs.count == 4)
        #expect(model.draft.form.legs[0].toIata == "LHR" && model.draft.form.legs[1].fromIata == "LHR")
        await model.flush()
        #expect(try await store.recover()?.state.step == .returnFlight)
        try await model.discard()
        try await database.close()
    }

    @Test func splitsLastLegAndJoinsOnlyTheRemovedStopsFlights() throws {
        var form = try WizardForm(input: generationInput())
        let first = form.legs[0]
        let destination = first.toIata
        form.insertStop(stop, beforeDestinationOf: 0)
        form.legs[0].arriveLocal = "2026-11-11T08:00"
        form.legs[1].departLocal = "2026-11-11T10:00"
        form.legs[1].arriveLocal = "2026-11-12T09:00"
        let firstFlight = form.legs[0]
        form.insertStop(second, beforeDestinationOf: 1)
        #expect(form.route().map(\.iata) == [first.fromIata, "DXB", "HEL", destination])
        #expect(form.legs[0] == firstFlight)
        #expect(form.legs[1].departLocal == "2026-11-11T10:00" && form.legs[1].arriveLocal.isEmpty)
        #expect(form.legs[2].departLocal.isEmpty && form.legs[2].arriveLocal.isEmpty)
        form.legs[2].arriveLocal = "2026-11-12T12:00"
        form.removeStop(at: 2)
        #expect(form.route().map(\.iata) == [first.fromIata, "DXB", destination])
        #expect(form.legs[0] == firstFlight)
        #expect(form.legs[1].departLocal == "2026-11-11T10:00")
        #expect(form.legs[1].arriveLocal == "2026-11-12T12:00")
        form.makeDirect()
        #expect(form.route().map(\.iata) == [first.fromIata, destination])
        #expect(form.legs[0].departLocal == first.departLocal)
        #expect(form.legs[0].arriveLocal == "2026-11-12T12:00")
        #expect(form.stays.count == 1)
    }

    @Test func returnStopsKeepBoundaryAndDirectDoesNotTouchTheOtherRoute() throws {
        var form = try WizardForm(input: generationInput())
        form.insertStop(stop, beforeDestinationOf: 0)
        form.addReturn()
        form.setRouteAirport(second, at: 1, home: true)
        form.insertStop(stop, beforeDestinationOf: 2)
        let home = Array(form.legs.dropFirst(2))
        form.makeDirect()
        #expect(form.returnBoundary == 1 && form.legs.count == 3)
        #expect(Array(form.legs.dropFirst(1)) == home)
        let outbound = form.legs[0]
        form.makeDirect(home: true)
        #expect(form.legs.count == 2 && form.legs[0] == outbound)
        #expect(form.route(home: true).map(\.iata) == [outbound.toIata, "HEL"])
    }

    @Test func editingAStopDerivesBothAdjacentEndpointsAndHonorsTheTotalLimit() throws {
        var form = try WizardForm(input: generationInput())
        form.insertStop(stop, beforeDestinationOf: 0)
        form.setRouteAirport(second, at: 1)
        #expect(form.legs[0].toIata == "HEL" && form.legs[1].fromIata == "HEL")
        form.addReturn()
        while form.legs.count < WizardForm.maxFlights {
            form.insertStop(stop, beforeDestinationOf: form.returnBoundary - 1)
        }
        let limit = form
        form.insertStop(second, beforeDestinationOf: form.returnBoundary - 1)
        form.insertStop(second, beforeDestinationOf: form.legs.count - 1)
        #expect(form == limit && form.stays.count == 16)
    }

    @Test @MainActor func routeEditingLocksAndFollowsHomeAndBackKeepsStops() async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        var draft = try await store.start()
        draft.form = try WizardForm(input: generationInput())
        draft.form.addReturn()
        draft.form.setRouteAirport(
            wizardAirport(draft.form.legs[0].fromIata, city: "Origin", zone: "UTC"), at: 1, home: true)
        let model = MemberWizardModel(draft: draft, store: store, search: noAirportSearch())
        model.chooseAirport(stop, sheet: WizardAirportSheet(index: 0, side: .stop))
        let route = model.draft.form.route()
        model.swapAirports()
        #expect(model.draft.form.route() == route)
        model.go(.outbound)
        model.popNavigation(to: [], from: [.outbound])
        #expect(model.draft.state.step == .whereTo && model.draft.form.route() == route)
        model.chooseAirport(second, sheet: WizardAirportSheet(index: 0, side: .from))
        #expect(model.draft.form.legs.last?.toIata == "HEL")
        model.chooseAirport(second, sheet: WizardAirportSheet(index: 1, side: .to))
        #expect(model.draft.form.legs[2].fromIata == "HEL")
        model.chooseAirport(stop, sheet: WizardAirportSheet(index: 2, side: .from))
        #expect(model.draft.form.legs[2].fromIata == "HEL")
        model.chooseAirport(stop, sheet: WizardAirportSheet(index: 2, side: .home))
        model.chooseAirport(
            wizardAirport("LHR", city: "London", zone: "Europe/London"),
            sheet: WizardAirportSheet(index: 0, side: .from))
        #expect(model.draft.form.legs.last?.toIata == "DXB")
        model.go(.returnRoute)
        model.finishReturnRoute()
        #expect(model.draft.state.returnRouteConfirmed == true && model.draft.state.step == .returnFlight)
        #expect(model.navigationPath == [.outbound, .returnChoice, .returnRoute, .returnFlight])
        let path = model.navigationPath
        model.popNavigation(to: Array(path.dropLast()), from: path)
        #expect(model.draft.state.step == .returnRoute)
        model.makeDirect()
        model.swapAirports()
        #expect(model.draft.form.route().map(\.iata) == ["HEL", "LHR"])
        await model.flush()
        #expect(try await store.recover() == model.draft)
        try await model.discard()
        try await database.close()
    }

    @Test(arguments: [false, true]) func recoveryDecodesOldReturnFlightAndPreservesConfirmedTimes(_ confirmed: Bool)
        async throws
    {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        var draft = try await store.start()
        draft.form = try WizardForm(input: generationInput())
        draft.form.addReturn()
        draft.state.step = .returnFlight
        draft.state.returnRouteConfirmed = confirmed ? true : nil
        draft.state.revision += 1
        try await store.persist(draft)
        let recovered = try #require(try await store.recover())
        #expect(recovered.state.step == (confirmed ? .returnFlight : .returnRoute))
        #expect(recovered.form == draft.form)
        try await database.close()
    }

    @Test func mixedServerErrorsReturnToTheEarliestScreenInPathOrder() throws {
        var form = try WizardForm(input: generationInput())
        form.insertStop(stop, beforeDestinationOf: 0)
        form.addReturn()
        form.insertStop(second, beforeDestinationOf: 2)
        for (paths, step) in [
            (["legs.0.arriveLocal", "legs.2.toIata"], MemberWizardStep.outbound),
            (["legs.1.departLocal", "legs.2.fromIata"], .outbound),
            (["legs.1.toIata", "legs.2.departLocal"], .whereTo),
            (["legs.0.toIata", "legs.2.toIata", "legs.1.departLocal"], .whereTo),
            (["legs.2.toIata", "legs.3.arriveLocal"], .returnRoute),
            (["legs.2.departLocal", "legs.3.arriveLocal"], .returnFlight),
        ] {
            let errors = Dictionary(uniqueKeysWithValues: paths.map { ($0, FieldMessage(key: "error")) })
            #expect(WizardJourney.errorStep(errors, form: form) == step)
        }
    }

    @Test func laterCardOwnsChronologyErrorAndServerFieldsReturnToTheirEditors() throws {
        var form = try WizardForm(input: generationInput())
        form.insertStop(stop, beforeDestinationOf: 0)
        form.legs[0].arriveLocal = "2026-11-11T12:00"
        form.legs[1].departLocal = "2026-11-11T11:00"
        let errors = WizardValidation.validate(form, airports: [stop.iata: stop])
        #expect(errors["legs.1.departLocal"]?.key == "This flight leaves before the previous one lands.")
        #expect(errors["legs.0.departLocal"] == nil)
        form.addReturn()
        for (path, step) in [
            ("legs.1.departLocal", MemberWizardStep.outbound), ("legs.1.toIata", .whereTo),
            ("legs.2.departLocal", .returnFlight), ("legs.2.toIata", .returnRoute), ("review", .returnFlight),
        ] {
            #expect(WizardJourney.errorStep([path: FieldMessage(key: "error")], form: form) == step)
        }
        let rejection = FieldMessage(key: "Your flight home must leave from the airport you landed at.")
        let mapped = WizardJourney.errors(["return.legs.0.from_iata": rejection], form: form)
        #expect(mapped == ["review": rejection])
        #expect(WizardJourney.errorStep(mapped, form: form) == .returnFlight)
    }
}
