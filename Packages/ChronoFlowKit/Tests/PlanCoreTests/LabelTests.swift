import AppCore
import Foundation
import Testing

@testable import PlanCore

struct LabelTests {
    @Test func optionalRulesAndUnknowns() throws {
        let optional: [BlockType: [Priority]] = [
            .avoidLight: [.optional], .seekLight: [.optional], .caffeineOK: [.core, .recommended, .optional, .info],
            .lightOK: [.info], .lightNeutral: [.info],
        ]
        for type in [
            BlockType.sleep, .nap, .rest, .seekLight, .lightOK, .lightNeutral, .avoidLight, .caffeineServing,
            .caffeineRoutine, .caffeineOK, .noCaffeine, .flight, .layover, .transfer, .movementBreak, .zoneChange,
            .note,
        ] {
            for priority in [Priority.core, .recommended, .optional, .info] {
                var item = try block("test", 0, 60)
                item.type = type
                item.priority = priority
                #expect(isOptionalStep(item) == (optional[type]?.contains(priority) ?? false))
            }
        }
        var item = try block("unknown", 0, 60)
        item.type = .unknown("future")
        #expect(
            layoutDay(try sampleDay(), blocks: [item], presentation: emptyIndex()).placed.values.allSatisfy {
                $0.isEmpty
            })
        item.type = .sleep
        item.lane = .unknown("future")
        #expect(
            layoutDay(try sampleDay(), blocks: [item], presentation: emptyIndex()).placed.values.allSatisfy {
                $0.isEmpty
            })
    }

    @Test func datesZonesAndIntervals() async throws {
        let f = CopyLineFormatter(catalog: try await CopyCatalog.load())
        var day = try sampleDay()
        for (lang, date, range, expected) in [
            (Language.en, "2026-10-15", nil, "Thu 15 Oct"), (.nl, "2026-10-15", nil, "do 15 okt"),
            (.en, "2026-10-15", "2026-10-15", "Thu 15 Oct"), (.en, "2026-10-15", "2026-10-16", "Thu 15 – Fri 16 Oct"),
            (.en, "2026-10-31", "2026-11-01", "Sat 31 Oct – Sun 1 Nov"),
            (.nl, "2026-10-31", "2026-11-01", "za 31 okt – zo 1 nov"),
        ] {
            day.labelDate = date
            day.labelRange = range
            #expect(f.dayDateLabel(day, language: lang) == expected)
        }
        #expect(f.formatDayMonth("2026-03-29", language: .en) == "29 Mar")
        #expect(f.formatMonthYear("2026-03-29", language: .nl) == "mrt 2026")
        #expect(localDate("2026-10-14T23:45Z", zone: "Asia/Tokyo") == "2026-10-15")
        #expect(localDate("2026-10-14T23:45Z", zone: "America/New_York") == "2026-10-14")
        var item = try block("sleep", 0, 60)
        item.displayTz = "Asia/Tokyo"
        item.startUtc = "2026-10-14T14:30Z"
        item.endUtc = "2026-10-14T22:30Z"
        #expect(f.blockInterval(item, options: .init(language: .en)) == "14 Oct 2026 23:30 – 15 Oct 2026 07:30")
        item.displayTz = "Europe/Amsterdam"
        item.startUtc = "2026-10-25T00:30Z"
        item.endUtc = "2026-10-25T01:30Z"
        #expect(f.blockInterval(item, options: .init(language: .en)) == "02:30 (GMT+02:00) – 02:30 (GMT+01:00)")
        #expect(utcOffset("2026-01-01T00:00Z", zone: "America/New_York") == "GMT-05:00")
        let from = AirportRef(iata: "JFK", city: "New York", zone: "America/New_York")
        let to = AirportRef(iata: "BOS", city: "Boston", zone: "America/New_York")
        var trip = TripDetailView(
            id: "trip", from: from, to: to, departLocal: "", departureUtc: "", endUtc: "", offsetDifferenceMin: 0,
            legs: [])
        #expect(zoneLabel(from.zone, trip: trip) == "New York")
        trip.from.city = nil
        #expect(zoneLabel(from.zone, trip: trip) == "Boston")
        trip.legs = [
            .init(
                position: 0, from: .init(iata: "NRT", city: "Narita", zone: "Asia/Tokyo"),
                to: .init(iata: "HND", city: "Tokyo", zone: "Asia/Tokyo"), returnLeg: false)
        ]
        #expect(zoneLabel("Asia/Tokyo", trip: trip) == "Narita")
        #expect(zoneLabel("America/Argentina/Buenos_Aires") == "Buenos Aires")
        #expect(zoneLabel("UTC") == "UTC")
        let arg = CopyArg(name: "untilUtc", kind: .instant, value: .string("2026-01-15T00:00Z"), tz: "Asia/Tokyo")
        #expect(
            f.formatArgument(
                arg,
                options: .init(
                    language: .en, timeFormat: .value12, displayZone: "UTC", annotateInstantZone: true, trip: trip))
                == "09:00 AM (Narita)")
        for language in [Language.en, .nl] {
            for (value, en, nl) in [
                ("00:05", "12:05 AM", "12:05 a.m."), ("03:00", "03:00 AM", "03:00 a.m."),
                ("11:59", "11:59 AM", "11:59 a.m."), ("12:00", "12:00 PM", "12:00 p.m."),
                ("15:00", "03:00 PM", "03:00 p.m."), ("23:59", "11:59 PM", "11:59 p.m."),
            ] {
                #expect(
                    f.formatInstant("2026-01-15T\(value)Z", options: .init(language: language, timeFormat: .value12))
                        == (language == .en ? en : nl))
            }
        }
    }

    @Test func summaryClippingSplittingAndMerging() async throws {
        var day = try sampleDay()
        day.startUtc = "2026-10-14T22:00Z"
        day.endUtc = "2026-10-15T22:00Z"
        day.zones = [
            .init(tz: "Europe/Amsterdam", startUtc: day.startUtc, endUtc: "2026-10-15T00:00Z"),
            .init(tz: "Asia/Tokyo", startUtc: "2026-10-15T00:00Z", endUtc: "2026-10-15T12:00Z"),
            .init(tz: "Europe/Amsterdam", startUtc: "2026-10-15T12:00Z", endUtc: day.endUtc),
        ]
        func sleep(_ start: String, _ end: String) throws -> BlockView {
            var item = try block("main", 0, 60)
            item.startUtc = start
            item.endUtc = end
            item.params = .sleep(.init(kind: .main, setting: .bed, opportunityMin: 60))
            return item
        }
        let intervals = summaryIntervals(
            day, blocks: try [sleep("2026-10-14T20:00Z", "2026-10-16T01:00Z")], type: .sleep)
        #expect(intervals.count == 3 && intervals.map(\.tz) == ["Europe/Amsterdam", "Asia/Tokyo", "Europe/Amsterdam"])
        #expect(intervals.first?.start == planDate(day.startUtc) && intervals.last?.end == planDate(day.endUtc))
        let merged = summaryIntervals(
            day,
            blocks: try [
                sleep("2026-10-15T01:00Z", "2026-10-15T04:00Z"), sleep("2026-10-14T23:00Z", "2026-10-15T01:00Z"),
                sleep("2026-10-15T03:00Z", "2026-10-15T05:00Z"), sleep("2026-10-15T06:00Z", "2026-10-15T07:00Z"),
            ], type: .sleep)
        #expect(
            merged.count == 3 && merged[1].start == planDate("2026-10-15T00:00Z")
                && merged[1].end == planDate("2026-10-15T05:00Z"))
        var recovery = try sleep(day.startUtc, day.endUtc)
        recovery.params = .sleep(.init(kind: .inFlightRecovery, setting: .bed, opportunityMin: 60))
        #expect(summaryIntervals(day, blocks: [recovery], type: .sleep).isEmpty)
        #expect(
            summaryIntervals(
                day, blocks: try [sleep("2026-10-14T20:00Z", day.startUtc), sleep(day.endUtc, "2026-10-15T23:00Z")],
                type: .sleep
            ).isEmpty)
        #expect(dayZoneLabel(day) == "Amsterdam → Tokyo")
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        let layout = layoutDay(day, blocks: [], presentation: emptyIndex())
        #expect(
            formatter.nowLabel(layout, now: planDate("2026-10-15T01:00Z"), options: .init(language: .en)) == "10:00")
    }

    @Test func noticesStatusAndLabelCatalog() async throws {
        let catalog = try await CopyCatalog.load()
        let f = try fixture()
        for type in Set(f.plan.blocks.map(\.type)) { #expect(catalog.contains(try #require(stepLabelKey(type)))) }
        for phase in [LabelPhase.preDeparture, .travel, .travelArrivalNight, .arrivalDay0, .day] {
            #expect(catalog.contains(try #require(dayLabelKey(phase))))
        }
        for status in [DayStatus.adapting, .partiallyAdapted, .adapted, .adaptedSlowerClock] {
            #expect(catalog.contains(try #require(dayStatusLabelKey(status))))
        }
        var plan = f.plan
        var day = plan.days[0]
        let note = NoteView(role: .info, clinicianLink: false, lines: [.init(key: "Sleep", args: [])])
        plan.warnings = [note]
        day.notes = [note, note]
        let notices = PlanNoticesView(
            days: [.init(dayId: day.id, warningIndexes: [0, 0])], unassignedWarningIndexes: [])
        #expect(noticeItems(plan, notices: notices, day: day) == [.init(note: note, warning: true)])
        let card = TripCardView(
            id: "trip", from: .init(iata: "AMS", zone: "Europe/Amsterdam"), to: .init(iata: "NRT", zone: "Asia/Tokyo"),
            departLocal: "", arriveLocal: "", departureUtc: at(0), arrivalUtc: at(60), connections: [],
            offsetDifferenceMinutes: 0, progress: .init(status: .upcoming), canComplete: false, canReopen: false,
            canEdit: false, canDuplicate: false, canDelete: false)
        for (minute, status) in [(-1.0, TripStatus.upcoming), (0, .active), (59, .active), (60, .completed)] {
            #expect(
                tripDisplayStatus(card, planStartUtc: at(0), planEndUtc: at(60), now: planDate(at(minute))) == status)
        }
        #expect(tripDisplayStatus(card, planStartUtc: nil, planEndUtc: at(60), now: planDate(at(30))) == .upcoming)
        var completed = card
        completed.progress.status = .completed
        #expect(
            tripDisplayStatus(completed, planStartUtc: at(0), planEndUtc: at(60), now: planDate(at(-1))) == .completed)
    }
}
