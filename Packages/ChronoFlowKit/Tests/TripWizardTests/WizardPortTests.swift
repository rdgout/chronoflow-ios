import AppCore
import Foundation
import Testing
import TripWizard

@Suite struct WizardDateTimeTests {
    @Test func leapDaysAndMonths() throws {
        #expect(WizardDateTime.shiftDate("2028-02-28", days: 1) == "2028-02-29")
        #expect(WizardDateTime.shiftDate("2026-12-31", days: 1) == "2027-01-01")
        #expect(
            WizardDateTime.formatLocal("2026-11-01T00:07", locale: Locale(identifier: "en_GB"))?.contains("00:07")
                == true)
    }

    @Test(arguments: [
        "2026-02-30T12:00", "2026-11-01T24:00", "2026-11-01T12:60", "2026-11-01", "", "invalid", "0000-01-01T12:00",
    ])
    func rejectsInvalid(_ value: String) { #expect(WizardDateTime.date(value) == nil) }

    @Test(arguments: ["2026-11-01T10:07", "2027-01-01T00:00", "2027-03-28T02:30", "2026-10-25T02:30"])
    func pickerPreservesMinutesAcrossDeviceDSTChanges(_ value: String) throws {
        let picker = try #require(WizardDateTime.pickerDate(value))
        #expect(WizardDateTime.pickedValue(picker) == value)
        for deviceZone in ["Europe/Amsterdam", "America/New_York", "Asia/Tokyo"] {
            var device = Calendar(identifier: .gregorian)
            device.timeZone = try #require(TimeZone(identifier: deviceZone))
            _ = device.dateComponents([.hour, .minute], from: picker)
            #expect(WizardDateTime.pickedValue(picker) == value)
        }
    }

    @Test func actualPhoneGapIsValidAtAnotherAirport() throws {
        let value = "2027-03-28T02:30"
        #expect(WizardDateTime.instant(value, zone: "Europe/Amsterdam") == nil)
        #expect(WizardDateTime.instant(value, zone: "Asia/Tokyo") != nil)
        let picker = try #require(WizardDateTime.pickerDate(value))
        #expect(WizardDateTime.pickedValue(picker) == value)
        #expect(WizardDateTime.shiftDate(value, days: 1) == "2027-03-29")
        #expect(
            WizardDateTime.pickedValue(WizardDateTime.calendar.date(byAdding: .day, value: 1, to: picker)!)
                == "2027-03-29T02:30")
        #expect(WizardDateTime.pickerValue(nil, fallbackDate: "2026-11-02") == "2026-11-02T12:00")
        #expect(WizardDateTime.pickerValue("23:00", fallbackDate: "2026-11-02", dateTime: false) == "23:00")
        #expect(
            WizardDateTime.pickedValue(WizardDateTime.pickerDate("02:30", dateTime: false)!, dateTime: false) == "02:30"
        )
    }

    @Test func weekdayAndTimeRespectLocaleAndClock() {
        let value = "2026-10-12T23:25"
        #expect(WizardDateTime.formatWeekdayTime(value, locale: Locale(identifier: "en_GB")) == "Mon 23:25")
        #expect(WizardDateTime.formatWeekdayTime(value, locale: Locale(identifier: "nl_NL"))?.hasPrefix("ma") == true)
        #expect(
            WizardDateTime.formatWeekdayTime(value, locale: Locale(identifier: "en_GB"), twelveHour: true)?.contains(
                "11:25") == true)
        #expect(WizardDateTime.formatWeekdayTime("invalid", locale: .current) == "invalid")
        for (value, language, twelveHour, expected) in [
            ("2026-10-12T23:25", "en_GB", false, "Mon 23:25"),
            ("2026-10-13T18:05", "en_GB", false, "Tue 18:05"),
            ("2026-10-12T23:25", "nl_NL", false, "ma 23:25"),
            ("2026-10-13T18:05", "nl_NL", false, "di 18:05"),
            ("2026-10-12T23:25", "en_GB", true, "Mon 11:25 PM"),
            ("2026-10-13T18:05", "nl_NL", true, "di 06:05 p.m."),
            ("2026-11-01T00:07", "en_GB", false, "Sun 00:07"),
            ("2026-11-01T00:07", "en_GB", true, "Sun 12:07 AM"),
            ("2026-11-01T12:00", "nl_NL", true, "zo 12:00 p.m."),
            ("2026-12-31T23:59", "en_GB", false, "Thu 23:59"),
            ("2027-01-01T00:01", "nl_NL", false, "vr 00:01"),
        ] {
            #expect(
                WizardDateTime.formatWeekdayTime(value, locale: Locale(identifier: language), twelveHour: twelveHour)
                    == expected)
        }
    }
}

@Suite struct WizardValidationTests {
    @Test func blankErrorsMatchRN() {
        #expect(
            WizardValidation.validate(WizardForm()) == [
                "legs.0.fromIata": FieldMessage(key: "Choose the airport you leave from."),
                "legs.0.toIata": FieldMessage(key: "Choose the airport you land at."),
                "legs.0.departLocal": FieldMessage(key: "Please fill this in."),
                "legs.0.arriveLocal": FieldMessage(key: "Please fill this in."),
            ])
    }

    @Test func airportCountsSleepBusyAndLimits() throws {
        var form = try WizardForm(input: generationInput())
        form.legs[0].toIata = form.legs[0].fromIata
        form.legs[0].airportTransferMin = -1
        form.legs[0].flightNumber = String(repeating: "A", count: 13)
        form.end.kind = "nights"
        form.end.nights = 0
        form.override.enabled = true
        form.override.habitualBed = "25:00"
        form.preparation.days = 5
        form.preparation.feasibleNightBed = "21:00"
        form.preparation.busyIntervals = [WizardBusy(startLocal: "2026-11-01T13:00", endLocal: "2026-11-01T12:00")]
        let errors = WizardValidation.validate(form)
        for path in [
            "legs.0.toIata", "legs.0.airportTransferMin", "legs.0.flightNumber", "end.nights", "override.habitualBed",
            "override.habitualWake", "preparation.days", "preparation.feasibleNightBed",
            "preparation.busyIntervals.0.endLocal",
        ] {
            #expect(errors[path] != nil)
        }
        form.stays = []
        #expect(WizardValidation.validate(form)["legs"] != nil)
        form.end.kind = "check_out"
        form.end.checkOutDate = "2026-02-30"
        #expect(WizardValidation.validate(form)["end.checkOutDate"] != nil)
        form.end.kind = "return_legs"
        form.end.returnFromLeg = 0
        #expect(WizardValidation.validate(form)["end.returnFromLeg"] != nil)
    }

    @Test func differentAirportWallTimesDoNotEstablishChronology() throws {
        var form = try WizardForm(input: generationInput())
        form.legs[0].fromIata = "SYD"
        form.legs[0].toIata = "LAX"
        form.legs[0].departLocal = "2026-11-01T22:00"
        form.legs[0].arriveLocal = "2026-11-01T18:00"
        #expect(WizardValidation.validate(form).isEmpty)
    }

    @Test(arguments: ["", "2026-02-30T12:00", "invalid"])
    func leaveTimeDoesNotCompareAgainstInvalidDeparture(_ departure: String) throws {
        var form = try WizardForm(input: generationInput())
        form.legs[0].departLocal = departure
        form.legs[0].leaveForAirportLocal = "2026-11-01T12:00"
        let errors = WizardValidation.validate(form)
        #expect(
            errors["legs.0.departLocal"]?.key
                == (departure.isEmpty ? "Please fill this in." : "Enter a valid date and time."))
        #expect(errors["legs.0.leaveForAirportLocal"] == nil)
    }

    @Test func leaveAndConnectionOrderAndContinuity() throws {
        var form = try WizardForm(input: generationInput())
        form.legs[0].leaveForAirportLocal = form.legs[0].departLocal
        #expect(WizardValidation.validate(form)["legs.0.leaveForAirportLocal"] != nil)
        form.addFlight()
        form.legs[1].toIata = "SIN"
        form.legs[1].departLocal = form.legs[0].arriveLocal
        form.legs[1].arriveLocal = "2026-11-15T12:00"
        #expect(WizardValidation.validate(form)["legs.1.departLocal"] != nil)
        form.legs[1].fromIata = "DXB"
        #expect(
            WizardValidation.validate(form)["legs.1.fromIata"]?.key
                == "Start this flight where the previous flight lands.")
    }

    @Test func errorMappingAndSections() {
        var form = WizardForm()
        form.addFlight()
        form.addReturn()
        form.addFlight(home: true)
        let cases = [
            "outbound.legs.0.arrive_local": "legs.0.arriveLocal", "return.legs.0.flight_number": "legs.2.flightNumber",
            "return.legs.0.stay.busy_intervals.2.start_local": "stays.2.busyIntervals.2.startLocal",
            "outbound.legs.0.stay": "stays.0", "trip_end_nights": "end.nights",
            "pre_departure_busy_intervals.0.end_local": "preparation.busyIntervals.0.endLocal",
            "override.use": "override.enabled", "profile.cups_filter_coffee": "profile.cupsFilterCoffee",
        ]
        for (raw, mapped) in cases { #expect(WizardJourney.errorPath(raw, form: form) == mapped) }
        for index in 0..<4 {
            for field in [
                "fromIata", "toIata", "departLocal", "arriveLocal", "flightNumber", "seatLieFlat", "seatWindow",
            ] {
                #expect(
                    WizardValidation.errorSection("legs.\(index).\(field)", form: form)
                        == FieldMessage(
                            key: index < 2 ? "Outbound, flight {{number}}" : "Return, flight {{number}}",
                            arguments: ["number": .number(Decimal(index + 1))]))
            }
        }
        for (path, section) in [
            "legs.0.leave_for_airport_local": "Leaving for the airport",
            "legs.0.airport_transfer_min": "Leaving for the airport",
            "stays.1.bed_available_from_local": "Arrival", "stays.1.check_out_local": "End of stay",
            "stays.2.busy_intervals.0.end_local": "Nights at your destination",
            "trip_end_nights": "Nights at your destination",
            "trip_end_check_out_date": "End of stay", "preparation_days": "Preparation",
            "fast_delay_opt_in": "Preparation",
            "latest_wake": "Preparation", "feasible_night_bed": "Preparation", "feasible_night_wake": "Preparation",
            "pre_departure_busy_answered": "Preparation", "pre_departure_busy_intervals.0.end_local": "Preparation",
            "use_profile_override": "Your sleep for this trip", "override_habitual_bed": "Your sleep for this trip",
            "override_habitual_wake": "Your sleep for this trip", "override_chronotype": "Your sleep for this trip",
        ] {
            let normalized = WizardJourney.errorPath(path, form: form)
            #expect(WizardValidation.errorSection(path, form: form).key == section)
            #expect(WizardValidation.errorSection(normalized, form: form).key == section)
        }
        for path in [
            "legs", "end.kind", "end.returnFromLeg", "trip_end_kind", "return_from_leg", "stays", "legs.99.departLocal",
            "stays.99.checkOutLocal", "legs.invalid.departLocal", "unknown",
        ] {
            #expect(WizardValidation.errorSection(path, form: form).key == "Your flights")
        }
        let mapped = WizardValidation.validationErrors(
            [
                "review_expired": FieldMessage(key: "expired"), "review": FieldMessage(key: "review"),
                "credits": FieldMessage(key: "credits"),
                "legs.1.arrive_local": FieldMessage(key: "error", arguments: ["number": .number(2)]),
            ], form: form)
        #expect(mapped == ["legs.1.arriveLocal": FieldMessage(key: "error", arguments: ["number": .number(2)])])
    }
}

@Suite struct WizardFormTests {
    @Test func independentDefaults() {
        let first = WizardForm()
        let second = WizardForm()
        #expect(first.legs.count == 1 && first.stays == [WizardStay()])
        #expect(first.legs[0].id != second.legs[0].id)
        #expect(
            first.identity == nil && first.itinerary == nil && first.end.kind == "one_way"
                && first.preparation.days == 3)
    }

    @Test(arguments: [0, 1, 2, 3])
    func removeRestoreKeepsStayBoundaryAndLaterChanges(_ index: Int) throws {
        var form = WizardForm()
        form.addFlight()
        form.addReturn()
        form.addFlight(home: true)
        let original = form
        let taken = form.takeFlight(index)
        let removed = try #require(taken)
        #expect(form.end.returnFromLeg == (index < 2 ? 1 : 2))
        #expect(form.legs.count == 3 && form.stays.count == 3)
        form.restoreFlight(removed)
        #expect(form == original)
        form.restoreFlight(removed)
        #expect(form == original)
        _ = form.takeFlight(index)
        form.legs[0].flightNumber = "KL 861"
        form.stays[0].arrivalTransferMin = 75
        let retainedID = form.legs[0].id
        form.restoreFlight(removed)
        #expect(form.legs.first { $0.id == retainedID }?.flightNumber == "KL 861")
    }

    @Test func returnRetentionLimitsAndOutboundPropagation() {
        var form = WizardForm()
        form.end.kind = "nights"
        form.end.nights = 8
        form.updateLeg(0) {
            $0.toIata = "NRT"
            $0.toCity = "Tokyo"
        }
        form.addReturn()
        form.legs[1].flightNumber = "EK 148"
        let firstRemoval = form.takeFlight(0)
        let secondRemoval = form.takeFlight(1)
        #expect(firstRemoval == nil && secondRemoval == nil)
        let returnedID = form.legs[1].id
        form.addFlight()
        #expect(form.legs[1].fromIata == "NRT" && form.legs[2].id == returnedID && form.returnBoundary == 2)
        form.updateLeg(1) {
            $0.toIata = "SIN"
            $0.toCity = "Singapore"
        }
        #expect(form.legs[2].fromIata == "SIN")
        let retained = form.removeReturn()
        #expect(form.end.kind == "nights" && form.end.nights == 8)
        form.addReturn(retained)
        #expect(form.legs.last?.flightNumber == "EK 148" && form.legs[form.returnBoundary].fromIata == "SIN")
        while form.legs.count < WizardForm.maxFlights { form.addFlight(home: true) }
        let limit = form
        form.addFlight()
        form.addFlight(home: true)
        #expect(form == limit && form.stays.count == WizardForm.maxFlights)
    }

    @Test func stopSplitsMiddleTimesAndRemovalJoinsEndpoints() throws {
        var form = try WizardForm(input: generationInput())
        let before = form
        form.insertStop(wizardAirport("DXB", city: "Dubai", zone: "Asia/Dubai"), beforeDestinationOf: 0)
        #expect(form.legs.count == 2 && form.stays.count == 2)
        #expect(form.legs[0].departLocal == before.legs[0].departLocal && form.legs[0].arriveLocal.isEmpty)
        #expect(form.legs[1].departLocal.isEmpty && form.legs[1].arriveLocal.isEmpty)
        form.legs[1].arriveLocal = before.legs[0].arriveLocal
        form.removeStop(at: 1)
        #expect(form == before)
    }

    @Test(arguments: ["return_legs", "nights", "check_out", "one_way"])
    func roundTripsAllFieldsWithoutLeakingLocalMetadata(_ kind: String) throws {
        var form = try WizardForm(input: generationInput())
        form.addReturn()
        form.end.kind = kind
        form.end.nights = 5
        form.end.checkOutDate = "2027-01-15"
        form.end.returnFromLeg = kind == "return_legs" ? 1 : nil
        for index in form.legs.indices {
            form.legs[index].fromCity = "Origin \(index)"
            form.legs[index].toCity = "Destination \(index)"
            form.legs[index].flightNumber = "CF\(index)"
            form.legs[index].seatLieFlat = true
            form.legs[index].seatWindow = index == 0 ? "left" : "right"
            form.legs[index].leaveForAirportLocal = "2027-01-10T07:15"
            form.legs[index].airportTransferMin = 90
            form.stays[index].bedAvailableMode = "declared"
            form.stays[index].bedAvailableFromLocal = "2027-01-10T15:00"
            form.stays[index].checkOutLocal = "2027-01-15T11:00"
            form.stays[index].lateCheckOutOrDayRoom = true
            form.stays[index].arrivalTransferMin = 45
            form.stays[index].transferMode = "self_driven"
            form.stays[index].busyIntervals = [WizardBusy(startLocal: "2027-01-10T10:00", endLocal: "2027-01-10T12:00")]
        }
        form.override.enabled = true
        form.override.habitualBed = "22:15"
        form.override.habitualWake = "06:30"
        form.override.chronotype = "early"
        form.preparation.days = 4
        form.preparation.fastDelayOptIn = true
        form.preparation.latestWake = "08:15"
        form.preparation.feasibleNightBed = "00:30"
        form.preparation.feasibleNightWake = "09:00"
        form.preparation.busyAnswered = true
        form.preparation.busyIntervals = form.stays[0].busyIntervals
        form.identity = ApiReviewIdentity(
            token: "draft-token", inputRevision: 2, reviewRevision: 3, sourceRevision: "source")
        let input = form.reviewInput(identity: form.identity, profile: JSONObject(["age_band": .string("18_64")]))
        #expect(try WizardForm(reviewInput: input, retained: form) == form)
        #expect(input.input.outbound.legs.count == (kind == "return_legs" ? 1 : 2))
        let json = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
        #expect(!json.contains("fromCity") && !json.contains("Origin") && !json.contains(form.legs[0].id))
        #expect(form.reviewInput(identity: nil).identity == nil)
        let snapshot = ApiTripInputSnapshot(
            input: input.input, sourceRevision: "source",
            airports: ["AMS": wizardAirport("AMS", city: "Amsterdam", zone: "Europe/Amsterdam")])
        #expect(try WizardForm(snapshot: snapshot).legs[0].fromCity == "Amsterdam")
    }
}

func wizardAirport(_ iata: String, city: String, zone: String) -> ApiAirportSuggestion {
    ApiAirportSuggestion(iata: iata, name: city, city: city, country: "", timezone: zone)
}
