import AppCore
import Foundation
import GRDB
import LocalStore
import Sync
import Testing

@testable import DataAccess

@Suite struct PlanDecodingTests {
    struct List: Decodable { let trips: [TripListItem] }

    struct Parts: Codable, Equatable {
        var plan: PlanView
        var notices: PlanNoticesView
        var timeline: TimelinePresentationView
    }

    @Test(arguments: ["S1", "S2", "S3", "S4", "S5", "S6", "S6-RETURN-10N"])
    func completePlans(name: String) throws {
        let value = try JSONDecoder().decode(Parts.self, from: fixture("plans/\(name).json"))
        #expect(value.plan.blocks.contains { $0.type == .flight })
        #expect(!value.plan.days.isEmpty)
        #expect(try JSONDecoder().decode(Parts.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func fullEnvelopesAndMissingNullableFields() throws {
        let items = try JSONDecoder().decode(List.self, from: fixture("trips/list.json")).trips
        let detail = try TripDetailResponse(data: fixture("trips/detail.json"))
        #expect(items.first?.card.id == detail.trip.id)
        #expect(items.first?.adaptation == detail.plan.summary?.adaptation)
        #expect(items.first?.planInputHash == detail.plan.meta.inputHash)
        func removingNulls(_ value: Any) -> Any {
            if let object = value as? [String: Any] {
                return object.filter { !($0.value is NSNull) }.mapValues(removingNulls)
            }
            if let array = value as? [Any] { return array.map(removingNulls) }
            return value
        }
        let object = try JSONSerialization.jsonObject(with: detail.data)
        let data = try JSONSerialization.data(withJSONObject: removingNulls(object))
        #expect(try TripDetailResponse(data: data).detail == detail.detail)
        #expect(throws: (any Error).self) { try TripDetailResponse(data: Data("{}".utf8)) }
    }

    @Test(arguments: [
        ("flight", #"{"legIndex":0,"fromIata":"AMS","toIata":"JFK","overnight":false,"approximateTrack":true}"#),
        ("layover", #"{"kind":"connection","iata":"AMS"}"#),
        ("transfer", #"{"direction":"arrival","mode":"passenger","modeAssumed":false}"#),
        ("movement_break", "{}"),
        ("zone_change", #"{"arrivalIata":"JFK","departureIata":"AMS","offsetMin":-360}"#),
        ("sleep", #"{"kind":"main","setting":"bed","opportunityMin":480}"#),
        ("nap", #"{"kind":"standard","setting":"seat","lengthMin":20}"#),
        ("rest", #"{"lengthMin":20}"#),
        ("avoid_light", #"{"setting":"home","reduced":false}"#),
        ("seek_light", #"{"source":"outdoor","coreMin":30}"#),
        ("light_ok", #"{"untilUtc":null}"#),
        ("light_neutral", #"{"untilUtc":null}"#),
        (
            "caffeine_serving",
            #"{"kind":"maintenance","amount":"one","chip":"one","combined":null,"drivingLine":false}"#
        ),
        ("caffeine_ok", #"{"amount":"one","drivingLine":false}"#),
        ("caffeine_routine", #"{"cups":2,"amountPerDrink":"one","singleByUtc":null,"lastByUtc":null}"#),
        ("no_caffeine", #"{"nextServingUtc":null,"exception":{"amount":"one","byUtc":"2026-10-13T12:00Z"}}"#),
        (
            "caffeine_serving",
            #"{"kind":"maintenance","amount":{"mg":80,"drinks":[]},"chip":{"drink":"tea","halves":2},"combined":null,"drivingLine":false}"#
        ),
        ("caffeine_ok", #"{"amount":{"mg":80,"drinks":[]},"drivingLine":false}"#),
        (
            "no_caffeine",
            #"{"nextServingUtc":null,"exception":{"amount":{"mg":80,"drinks":[]},"byUtc":"2026-10-13T12:00Z"}}"#
        ),
        ("note", #"{"note":{"role":"info","clinicianLink":false,"lines":[],"endState":null}}"#),
    ])
    func blockParameterVariants(type: String, params: String) throws {
        let value = try block(type: type, params: params)
        #expect(try JSONDecoder().decode(BlockView.self, from: JSONEncoder().encode(value)) == value)
        if type == "caffeine_routine" {
            guard case .caffeineRoutine(let routine) = value.params else {
                Issue.record("Expected string-amount caffeine routine")
                return
            }
            #expect(routine.amountPerDrink == "one" && routine.cups == 2)
        }
    }

    @Test func copyArgumentShapesAndFutureEnums() throws {
        let data = Data(
            #"{"key":"Test","args":[{"name":"place","kind":"place","value":"Tokyo"},{"name":"min","kind":"future","value":1.5},{"name":"mg","kind":"milligrams","value":80,"drinks":[{"drink":"future","halves":2}],"usualDrinks":2}]}"#
                .utf8)
        let line = try JSONDecoder().decode(CopyLine.self, from: data)
        #expect(line.args.count == 3)
        #expect(line.args[1] == .standard(CopyArg(name: "min", kind: .unknown("future"), value: .number(1.5))))
        guard case .caffeine(let caffeine) = line.args[2] else {
            Issue.record("Expected caffeine copy argument")
            return
        }
        #expect(caffeine.drinks.first?.drink == .unknown("future"))
        #expect(try JSONDecoder().decode(CopyLine.self, from: JSONEncoder().encode(line)) == line)
        #expect(try JSONDecoder().decode(CheckStatus.self, from: Data(#""future""#.utf8)) == .unknown("future"))
    }

    @Test func rawAPIBytesAndUnknownCheckSurviveStorageAndReconciliation() async throws {
        let future = try block(type: "future_step", lane: "future_lane", params: #"{"future":[1,null,"kept"]}"#)
        var detail = try TripDetailResponse(data: fixture("trips/detail.json")).detail
        detail.plan.blocks.append(future)
        let encoded = String(decoding: try JSONEncoder().encode(detail), as: UTF8.self)
        let text = " \n {\"futureEnvelope\":{\"preserve\":true}," + encoded.dropFirst() + " \n"
        let data = Data(text.utf8)
        let server = StubServer { _ in .init(200, text) }
        let source = APIDataSource(client: try server.client())
        let response = try await source.fetchTripDetail(id: detail.trip.id)
        #expect(response.data == data)
        #expect(response.plan.blocks.last?.type == .unknown("future_step"))
        #expect(response.plan.blocks.last?.lane == .unknown("future_lane"))
        #expect(!response.plan.renderableBlocks.contains { $0.id == future.id })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = AccountDatabase(applicationSupport: root)
        let accountID = "019a562b-8000-7000-8000-000000000001"
        try await database.open(accountID: accountID)
        let epoch = SyncEpoch(accountID: try AccountID(accountID), generation: 1)
        try await AccountRepository(database: database).upsert(
            AccountRecord(id: accountID, name: "Test", email: "test@example.com"))
        let tripID = detail.trip.id
        let card = try #require(JSONDecoder().decode(List.self, from: fixture("trips/list.json")).trips.first?.card)
        try await TripRepository(database: database).upsert(
            TripRecord(
                id: tripID, card: .encoding(card), currentInputHash: "listed",
                departureUtc: detail.trip.departureUtc))
        let mark = CheckOffChange(
            tripID: tripID, planInputHash: "old", type: .unknown("future_step"), localDate: "2026-10-13", ordinal: 1,
            status: .done)
        let row = try await OutboxRepository(database: database).enqueue(
            .checkOff(mark), now: Date(timeIntervalSince1970: 1_800_000_000),
            randomBytes: Array(repeating: 1, count: 10))
        let reconciler = CheckOffReconciler(pull: FullPull(database: database, source: source))
        let prepared = try await reconciler.prepare(row, epoch: epoch)
        var expected = mark
        expected.planInputHash = detail.plan.meta.inputHash
        #expect(try prepared?.change == .checkOff(expected))
        let stored = try #require(
            try await TripRepository(database: database).plan(tripID: tripID, inputHash: detail.plan.meta.inputHash))
        #expect(stored.detail.data == data)
        #expect(try stored.decodedDetail().plan.blocks.last == future)
        let marks = try await TripRepository(database: database).checks(
            tripID: tripID, inputHash: detail.plan.meta.inputHash)
        #expect(marks.contains { $0.type == "future_step" && $0.status == "done" })
        try await database.close()
        try await database.open(accountID: accountID)
        #expect(
            try await TripRepository(database: database).plan(tripID: tripID, inputHash: detail.plan.meta.inputHash)?
                .detail.data == data)
        try await database.close()
        try FileManager.default.removeItem(at: root)
    }

    @Test func unknownLaneOnKnownBlockIsNotRenderable() throws {
        let value = try block(type: "rest", lane: "future_lane", params: #"{"lengthMin":20}"#)
        #expect(value.type == .rest)
        #expect(value.lane == .unknown("future_lane"))
        #expect(!value.isSupported)
        #expect(try JSONDecoder().decode(BlockView.self, from: JSONEncoder().encode(value)) == value)
    }

    #if DEBUG
        @Test(arguments: [
            "2000-02-29T23:59:00Z", "2026-03-29T01:30:00Z", "2026-10-25T01:30:00Z", "2035-07-15T12:00:00Z",
        ])
        func mockTripsRebaseEveryTimestampAndDate(nowText: String) throws {
            let utcFormatter = ISO8601DateFormatter()
            func instant(_ value: String) -> Date {
                let normalized = value.count == 17 ? value.replacingOccurrences(of: "Z", with: ":00Z") : value
                return utcFormatter.date(from: normalized)!
            }
            let now = instant(nowText)
            let seed = try MockAppSeed.make(now: now)
            let account = try #require(seed.accounts[MockScenarioValues.demoID])
            let statuses = Set(account.trips.map { $0.card.progress.status })
            #expect(statuses == [.active, .upcoming, .completed])
            let originals = try JSONDecoder().decode(MockAppSeed.Fixtures.self, from: MockTripFixtures.fixtureData())
            for (index, trip) in account.trips.enumerated() {
                let old = originals.trips[index]
                let detail = try #require(account.details[trip.card.id])
                let before = try strings(in: old.detail)
                let after = try strings(in: detail)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: trip.card.from.zone)!
                let dayDelta = calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: instant(old.card.departureUtc)),
                    to: calendar.startOfDay(for: instant(trip.card.departureUtc))
                ).day!
                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.calendar = calendar
                dateFormatter.timeZone = calendar.timeZone
                dateFormatter.dateFormat = "yyyy-MM-dd"
                for (path, text) in before {
                    if text.hasSuffix("Z") && text.contains("T"), let new = after[path] {
                        let elapsed = instant(new).timeIntervalSince(instant(text))
                        #expect(abs(elapsed - Double(dayDelta) * 86400) <= 3600)
                    } else if !path.contains(".checkKey.") && !path.hasSuffix(".labelDate")
                        && !path.hasSuffix(".labelRange"),
                        text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
                    {
                        let shifted = calendar.date(
                            byAdding: .day, value: dayDelta, to: dateFormatter.date(from: text)!)!
                        #expect(after[path] == dateFormatter.string(from: shifted))
                    }
                }
                #expect(trip.card.from.zone == old.card.from.zone && trip.card.to.zone == old.card.to.zone)
                #expect(detail.trip.departLocal == trip.card.departLocal)
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(identifier: trip.card.to.zone)!
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                #expect(trip.card.arriveLocal == formatter.string(from: instant(trip.card.arrivalUtc)))
                #expect(detail.plan.meta.inputHash == trip.planInputHash)
                #expect(detail.checkState.planInputHash == trip.planInputHash)
                #expect(detail.plan.meta.inputHash != old.detail.plan.meta.inputHash)
                #expect(detail.detailVersion != old.detail.detailVersion)
                for day in detail.plan.days {
                    formatter.timeZone = TimeZone(identifier: day.zones.first!.tz)!
                    #expect(day.labelDate == String(formatter.string(from: instant(day.startUtc)).prefix(10)))
                }
                for block in detail.plan.blocks {
                    if let key = block.checkKey {
                        formatter.timeZone = TimeZone(identifier: block.displayTz)!
                        #expect(key.localDate == String(formatter.string(from: instant(block.startUtc)).prefix(10)))
                    }
                    if case .zoneChange(let params) = block.params {
                        let airports = detail.trip.legs.flatMap { [$0.from, $0.to] }
                        let from = try #require(airports.first { $0.iata == params.departureIata })
                        let to = try #require(airports.first { $0.iata == params.arrivalIata })
                        let at = instant(block.startUtc)
                        #expect(
                            params.offsetMin
                                == (TimeZone(identifier: to.zone)!.secondsFromGMT(for: at)
                                    - TimeZone(identifier: from.zone)!.secondsFromGMT(for: at)) / 60)
                    }
                }
                for tick in detail.timeline.days.flatMap(\.ticks) {
                    #expect(
                        tick.offsetMin == TimeZone(identifier: tick.tz)!.secondsFromGMT(
                            for: instant(tick.atUtc)) / 60)
                }
                switch trip.card.progress.status {
                case .active:
                    #expect(instant(trip.planStartUtc) <= now && now < instant(trip.planEndUtc))
                    #expect(trip.keepOffline)
                case .upcoming: #expect(now < instant(trip.planStartUtc))
                case .completed: #expect(now >= instant(trip.planEndUtc) && !trip.keepOffline)
                case .unknown: Issue.record("Unexpected mock status")
                }
            }
        }

        private func strings(in value: some Encodable) throws -> [String: String] {
            let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
            func walk(_ value: JSONValue, path: String) -> [String: String] {
                switch value {
                case .string(let text): return [path: text]
                case .array(let items):
                    return items.enumerated().reduce(into: [:]) { result, item in
                        result.merge(walk(item.element, path: "\(path).\(item.offset)")) { _, next in next }
                    }
                case .object(let fields):
                    return fields.reduce(into: [:]) { result, item in
                        result.merge(walk(item.value, path: "\(path).\(item.key)")) { _, next in next }
                    }
                default: return [:]
                }
            }
            return walk(json, path: "")
        }
    #endif

    private func block(type: String, lane: String = "caffeine", params: String) throws -> BlockView {
        let text =
            #"{"id":"test-block","lane":"\#(lane)","type":"\#(type)","startUtc":"2026-10-13T10:00Z","endUtc":"2026-10-13T11:00Z","displayTz":"Europe/Amsterdam","priority":"optional","text":{"key":"Test","args":[]},"params":\#(params),"actionable":true,"checkKey":{"type":"\#(type)","localDate":"2026-10-13","ordinal":1}}"#
        return try JSONDecoder().decode(BlockView.self, from: Data(text.utf8))
    }
}
