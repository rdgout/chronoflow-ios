import AppCore
import Foundation
import Testing
import TripWizard

@Suite struct WizardFlightTimingTests {
    let airports = Dictionary(
        uniqueKeysWithValues: [
            ("AMS", "Europe/Amsterdam"), ("JFK", "America/New_York"), ("NRT", "Asia/Tokyo"),
            ("HNL", "Pacific/Honolulu"), ("AKL", "Pacific/Auckland"), ("LAX", "America/Los_Angeles"),
            ("SFO", "America/Los_Angeles"),
        ].map { code, zone in (code, wizardAirport(code, city: code, zone: zone)) })
    let now = WizardDateTime.date("2035-06-01T00:00")!

    @Test(arguments: [
        ("NRT", "HNL", "2026-11-12T21:00", "2026-11-12T02:00", "2026-11-12T09:00"),
        ("AKL", "LAX", "2026-11-12T08:00", "2026-11-11T11:00", "2026-11-11T21:00"),
        ("AMS", "JFK", "2026-11-12T14:00", "2026-11-12T08:00", "2026-11-12T16:00"),
        ("JFK", "AMS", "2026-11-12T21:00", "2026-11-13T03:00", "2026-11-13T10:00"),
        ("NRT", "SFO", "2026-11-12T17:00", "2026-11-12T00:00", "2026-11-12T10:00"),
    ])
    func arrivalBoundsAndEmptyStartConvertInstants(
        from: String, to: String, departure: String, minimum: String, arrival: String
    ) {
        var form = route([from, to])
        form.legs[0].departLocal = departure
        let timing = WizardFlightTiming(form: form, airports: airports)
        #expect(timing.minimumLocal(for: .arrival(0)).map(WizardDateTime.string) == minimum)
        #expect(WizardDateTime.string(timing.initialLocal(for: .arrival(0), now: now)) == minimum)
        #expect(timing.minimumLocal(for: .departure(0)) == nil)
        form.legs[0].arriveLocal = arrival
        #expect(WizardOutboundRules.errors(form: form, airports: airports, now: now, checkPast: false).isEmpty)
        let filled = WizardFlightTiming(form: form, airports: airports)
        #expect(WizardDateTime.string(filled.initialLocal(for: .arrival(0), now: now)) == arrival)
    }

    @Test func boundsChainThroughOutboundAndEveryHomeFlight() {
        var form = route(["NRT", "HNL", "LAX", "JFK", "AMS"])
        form.end.kind = "return_legs"
        form.end.returnFromLeg = 2
        let values = [
            ("2026-11-12T21:00", "2026-11-12T09:00"),
            ("2026-11-12T12:00", "2026-11-12T20:00"),
            ("2026-11-20T10:00", "2026-11-20T18:00"),
            ("2026-11-20T21:00", "2026-11-21T10:00"),
        ]
        for (index, value) in values.enumerated() {
            form.legs[index].departLocal = value.0
            form.legs[index].arriveLocal = value.1
        }
        #expect(WizardFlightRules.errors(form: form, airports: airports, now: now, checkPast: false).isEmpty)
        form.legs[1].departLocal = "2026-11-12T08:59"
        #expect(
            WizardOutboundRules.errors(form: form, airports: airports, now: now, checkPast: false)[
                "legs.1.departLocal"]?.key
                == "This flight leaves before the previous one lands.")
        form.legs[1].departLocal = values[1].0
        for index in 1..<form.legs.count {
            form.legs[index].departLocal = ""
            let timing = WizardFlightTiming(form: form, airports: airports)
            #expect(timing.minimumLocal(for: .departure(index)).map(WizardDateTime.string) == values[index - 1].1)
            #expect(WizardDateTime.string(timing.initialLocal(for: .departure(index), now: now)) == values[index - 1].1)
            form.legs[index].departLocal = values[index].0
        }
        form.legs[2].arriveLocal = ""
        let timing = WizardFlightTiming(form: form, airports: airports)
        #expect(timing.minimumLocal(for: .arrival(2)).map(WizardDateTime.string) == "2026-11-20T13:00")
        #expect(WizardDateTime.string(timing.initialLocal(for: .arrival(2), now: now)) == "2026-11-20T13:00")
    }

    @Test func unsetPredecessorHasNoBoundButStartFindsNearestEarlierSetField() {
        var form = route(["NRT", "HNL", "LAX", "JFK"])
        form.end.kind = "return_legs"
        form.end.returnFromLeg = 2
        form.legs[0].departLocal = "2026-11-12T21:00"
        form.legs[0].arriveLocal = "2026-11-12T09:00"
        var timing = WizardFlightTiming(form: form, airports: airports)
        #expect(timing.minimumLocal(for: .arrival(1)) == nil)
        #expect(WizardDateTime.string(timing.initialLocal(for: .arrival(1), now: now)) == "2026-11-12T11:00")
        #expect(timing.minimumLocal(for: .departure(2)) == nil)
        #expect(WizardDateTime.string(timing.initialLocal(for: .departure(2), now: now)) == "2026-11-12T11:00")
        form.legs[0].arriveLocal = ""
        timing = WizardFlightTiming(form: form, airports: airports)
        #expect(timing.minimumLocal(for: .departure(1)) == nil)
        #expect(WizardDateTime.string(timing.initialLocal(for: .departure(1), now: now)) == "2026-11-12T02:00")
    }

    @Test func noEarlierValuesUsesAirportLocalNowToTheMinuteAndIgnoresLaterValues() {
        var form = route(["NRT", "HNL"])
        var timing = WizardFlightTiming(form: form, airports: airports)
        let withSeconds = now.addingTimeInterval(37)
        #expect(timing.minimumLocal(for: .arrival(0)) == nil)
        #expect(WizardDateTime.string(timing.initialLocal(for: .departure(0), now: withSeconds)) == "2035-06-01T09:00")
        #expect(WizardDateTime.string(timing.initialLocal(for: .arrival(0), now: withSeconds)) == "2035-05-31T14:00")
        #expect(
            timing.initialLocal(for: .departure(0), now: withSeconds).timeIntervalSince1970.truncatingRemainder(
                dividingBy: 60) == 0)
        form.legs[0].arriveLocal = "2040-01-01T10:00"
        timing = WizardFlightTiming(form: form, airports: airports)
        #expect(WizardDateTime.string(timing.initialLocal(for: .departure(0), now: now)) == "2035-06-01T09:00")
        #expect(timing.minimumLocal(for: .departure(0)) == nil)
    }

    @Test(arguments: [
        ("2027-03-28T09:30", "2027-03-28T01:30"),
        ("2027-03-28T10:30", "2027-03-28T03:30"),
        ("2027-10-31T08:30", "2027-10-31T01:30"),
        ("2027-10-31T12:30", "2027-10-31T04:30"),
    ])
    func destinationDSTOffsetComesFromThePredecessorInstant(departure: String, minimum: String) {
        var form = route(["NRT", "AMS"])
        form.legs[0].departLocal = departure
        let timing = WizardFlightTiming(form: form, airports: airports)
        #expect(timing.minimumLocal(for: .arrival(0)).map(WizardDateTime.string) == minimum)
        #expect(WizardDateTime.string(timing.initialLocal(for: .arrival(0), now: now)) == minimum)
    }

    @Test(arguments: ["2027-03-28T01:30", "2027-03-28T03:30", "2027-10-31T02:30", "2027-10-31T03:30"])
    func sourceDSTResolutionMatchesExistingValidation(_ departure: String) throws {
        var form = route(["AMS", "JFK"])
        form.legs[0].departLocal = departure
        let instant = try #require(WizardDateTime.instant(departure, zone: "Europe/Amsterdam"))
        let timing = WizardFlightTiming(form: form, airports: airports)
        let local = try #require(timing.minimumLocal(for: .arrival(0)))
        #expect(WizardDateTime.instant(WizardDateTime.string(local), zone: "America/New_York") == instant)
    }

    @Test func nonexistentDSTSourceOrMissingZoneCannotEstablishABound() {
        var form = route(["AMS", "JFK"])
        form.legs[0].departLocal = "2027-03-28T02:30"
        #expect(WizardFlightTiming(form: form, airports: airports).minimumLocal(for: .arrival(0)) == nil)
        form.legs[0].departLocal = "2027-03-28T03:30"
        for missing in ["AMS", "JFK"] {
            let partial = airports.filter { $0.key != missing }
            #expect(WizardFlightTiming(form: form, airports: partial).minimumLocal(for: .arrival(0)) == nil)
        }
    }

    @Test func connectionValidationComparesInstantsThroughEachAirportZone() {
        var form = route(["NRT", "HNL", "LAX"])
        form.legs[0].arriveLocal = "2026-11-12T09:00"
        form.legs[1].fromIata = "LAX"
        form.legs[1].departLocal = "2026-11-12T10:00"
        let timing = WizardFlightTiming(form: form, airports: airports)
        #expect(timing.minimumLocal(for: .departure(1)).map(WizardDateTime.string) == "2026-11-12T11:00")
        #expect(
            WizardValidation.validate(form, airports: airports)["legs.1.departLocal"]?.key
                == "This flight leaves before the previous one lands.")
        form.legs[1].departLocal = "2026-11-12T12:00"
        #expect(WizardValidation.validate(form, airports: airports)["legs.1.departLocal"] == nil)
    }

    @Test @MainActor func changedEarlierValuesKeepStoredTimesAndValidationFlagsThem() async throws {
        let database = try await wizardDatabase()
        let store = MemberWizardStore(database: database)
        var draft = try await store.start()
        draft.form = route(["AMS", "JFK", "AMS", "NRT"])
        draft.form.end.kind = "return_legs"
        draft.form.end.returnFromLeg = 1
        draft.airports = airports
        let values = [
            ("2026-11-12T14:00", "2026-11-12T16:00"),
            ("2026-11-13T10:00", "2026-11-14T00:00"),
            ("2026-11-14T10:00", "2026-11-15T10:00"),
        ]
        for (index, value) in values.enumerated() {
            draft.form.legs[index].departLocal = value.0
            draft.form.legs[index].arriveLocal = value.1
        }
        let model = MemberWizardModel(draft: draft, store: store, search: noAirportSearch(), now: { self.now })
        model.setDateTime("2026-11-13T01:00", index: 0, arrival: false)
        #expect(model.minimumLocal(for: .arrival(0)).map(WizardDateTime.string) == "2026-11-12T19:00")
        #expect(WizardDateTime.string(model.initialLocal(for: .arrival(0))) == values[0].1)
        #expect(!model.finishOutbound())
        #expect(model.draft.fieldErrors["legs.0.arriveLocal"]?.key == "Check the departure and arrival times.")
        model.setDateTime("2026-11-13T12:00", index: 0, arrival: true)
        #expect(WizardDateTime.string(model.initialLocal(for: .departure(1))) == values[1].0)
        #expect(!model.finishReturn())
        #expect(
            model.draft.fieldErrors["legs.1.departLocal"]?.key == "This flight leaves before the previous one lands.")
        model.setDateTime("2026-11-14T12:00", index: 1, arrival: true)
        #expect(WizardDateTime.string(model.initialLocal(for: .departure(2))) == values[2].0)
        #expect(!model.finishReturn())
        #expect(
            model.draft.fieldErrors["legs.2.departLocal"]?.key == "This flight leaves before the previous one lands.")
        #expect(model.draft.form.legs[1].departLocal == values[1].0)
        #expect(model.draft.form.legs[2].departLocal == values[2].0)
        await model.flush()
        #expect(try await store.recover()?.form == model.draft.form)
        try await model.discard()
        try await database.close()
    }

    private func route(_ codes: [String]) -> WizardForm {
        var form = WizardForm()
        form.legs = zip(codes, codes.dropFirst()).map { from, to in
            var leg = WizardLeg(fromIata: from)
            leg.toIata = to
            return leg
        }
        form.stays = form.legs.map { _ in WizardStay() }
        return form
    }
}
