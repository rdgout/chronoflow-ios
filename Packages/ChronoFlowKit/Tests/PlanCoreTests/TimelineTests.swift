import AppCore
import Foundation
import Testing

@testable import PlanCore

struct PlanFixture: Decodable {
    var plan: PlanView
    var timeline: TimelinePresentationView
    var notices: PlanNoticesView
}

func fixture(_ name: String = "S1") throws -> PlanFixture {
    try JSONDecoder().decode(
        PlanFixture.self,
        from: Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!))
}

func at(_ minute: Double) -> String {
    Date(timeIntervalSince1970: 1_767_225_600 + minute * 60).ISO8601Format(.init(includingFractionalSeconds: true))
}

func sampleDay(_ hours: Double = 24) throws -> DayView {
    var day = try fixture().plan.days[0]
    day.startUtc = at(0)
    day.endUtc = at(hours * 60)
    day.zones = [.init(tz: "Europe/Amsterdam", startUtc: day.startUtc, endUtc: day.endUtc)]
    return day
}

func block(_ id: String, _ start: Double, _ end: Double) throws -> BlockView {
    var block = try #require(fixture().plan.blocks.first { $0.type == .sleep })
    block.id = id
    block.startUtc = at(start)
    block.endUtc = at(end)
    return block
}

func emptyIndex() -> TimelineIndex { indexTimeline(.init(days: [], blockReasons: [], transferWarnings: [])) }

struct TimelineTests {
    @Test func dimensionsPackingAndTinyTiles() throws {
        #expect(PlanMetrics.pointsPerHour == 40 && PlanMetrics.minTileHeight == 24 && PlanMetrics.tinyTileHeight == 56)
        #expect(PlanMetrics.gutterWidth == 44 && PlanMetrics.laneGap == 4 && PlanMetrics.tileInset == 2)
        #expect(timelineLanes == [.sleep, .light, .caffeine, .travel])
        let day = try sampleDay()
        let items = try [
            block("a", 0, 150), block("b", 15, 90), block("c", 90, 210), block("d", 225, 300), block("e", 225, 300),
            block("f", 300, 360),
        ]
        let result = layoutDay(day, blocks: items, presentation: emptyIndex()).placed[.sleep]!
        #expect(result.map(\.col) == [0, 1, 1, 0, 1, 0])
        #expect(result.map(\.cols) == [2, 2, 2, 2, 2, 1])
        #expect(result[2].top == 60 && result[2].height == 80 && !result[2].tiny)
        let short = layoutDay(
            day,
            blocks: try [
                block("before", -60, 20), block("short", 25, 26), block("end", 1439, 1441),
                block("instant", 1439, 1439),
            ], presentation: emptyIndex())
        let tiles = short.placed[.sleep]!
        #expect(tiles[0].continuesBefore && tiles[0].height == 24 && tiles[0].cols == 2 && tiles[0].tiny)
        #expect(tiles[1].col == 1)
        #expect(
            tiles[2].continuesAfter && tiles[2].top + tiles[2].height == short.height
                && tiles[2].exactTop > tiles[2].top)
        #expect(tiles[3].col == 1)
        for (duration, tiny) in [(0.0, true), (84.0, true), (84.01, false)] {
            #expect(
                layoutDay(day, blocks: try [block("tile", 0, duration)], presentation: emptyIndex()).placed[.sleep]![0]
                    .tiny == tiny)
        }
        #expect(layoutDay(day, blocks: [], presentation: emptyIndex()).minWidth == 236)
        #expect(
            layoutDay(
                day, blocks: try [block("a", 0, 100), block("b", 10, 60), block("c", 20, 50)],
                presentation: emptyIndex()
            ).minWidth == 282)
    }

    @Test func boundariesShortDaysAndLongDays() throws {
        let day = try sampleDay()
        let items = try [
            block("ends", -10, 0), block("before", -10, -10), block("start", 0, 0), block("end", 1440, 1440),
            block("after", 1440, 1450),
        ]
        #expect(
            layoutDay(day, blocks: items, presentation: emptyIndex()).placed[.sleep]!.map { $0.block.id } == ["start"])
        let short = layoutDay(
            try sampleDay(1.0 / 6), blocks: try [block("a", -1, 2), block("b", 9, 11)], presentation: emptyIndex())
        #expect(abs(short.height - 20.0 / 3) < 1e-8)
        #expect(short.placed[.sleep]!.allSatisfy { $0.top == 0 && $0.height == short.height && $0.cols == 2 })
        for hours in [23.0, 25.0, 31.0] {
            let long = try sampleDay(hours)
            #expect(layoutDay(long, blocks: [], presentation: emptyIndex()).height == hours * 40)
            #expect(nowLineOffset(long, now: planDate(at(hours * 30))) == hours * 20)
        }
        for (minute, expected) in [(-1.0, nil), (0, 0.0), (60, 40.0), (1439, 1439 * 2.0 / 3), (1440, nil), (1441, nil)]
        {
            let offset = nowLineOffset(day, now: planDate(at(minute)))
            if let expected { #expect(abs((offset ?? -100) - expected) < 1e-8) } else { #expect(offset == nil) }
        }
        #expect(nowLineOffset(day, now: Date(timeIntervalSince1970: .nan)) == nil)
        #expect(
            abs(
                nowLineOffset(day, now: planDate(day.startUtc).addingTimeInterval(0.001))! - PlanMetrics.pointsPerMinute
                    / 60_000) < 1e-8)
    }

    @Test func markersZonesAndTickThinning() throws {
        var day = try sampleDay()
        day.endUtc = at(270)
        day.zones = ["Europe/Amsterdam", "Asia/Dubai", "Asia/Tokyo"].enumerated().map {
            .init(tz: $0.element, startUtc: at(Double($0.offset * 90)), endUtc: at(Double(($0.offset + 1) * 90)))
        }
        var changes: [BlockView] = []
        for (i, minute) in [-2.0, 0, 90, 90, 270].enumerated() {
            var item = try block("change-\(i)", minute, minute + 5)
            item.type = .zoneChange
            changes.append(item)
        }
        #expect(zoneChangePositions(day, blocks: changes).map { $0.block.id } == ["change-1", "change-2", "change-3"])
        let shown = layoutDay(day, blocks: try [block("span", 30, 240)] + changes, presentation: emptyIndex())
        let hidden = layoutDay(day, blocks: changes, presentation: emptyIndex(), hidden: [.zoneChange])
        #expect(shown.height == 180 && shown.placed[.sleep]![0].height == 140)
        #expect(shown.dividers.map(\.top) == [60, 120])
        #expect(hidden.changes.isEmpty && hidden.dividers == shown.dividers)
        var notes: [BlockView] = []
        for (id, minute) in [("later", 80.0), ("first", 10), ("equal", 10), ("close", 11)] {
            var note = try block(id, minute, minute + 1)
            note.type = .note
            note.lane = .info
            notes.append(note)
        }
        let markers = layoutDay(day, blocks: notes, presentation: emptyIndex()).markers
        #expect(markers.map { $0.block.id } == ["first", "equal", "close", "later"])
        for i in markers.indices.dropFirst() {
            #expect(markers[i].top >= markers[i - 1].top + PlanMetrics.gutterMarkerSize)
        }
        #expect(layoutDay(day, blocks: notes, presentation: emptyIndex(), hidden: [.note]).markers.isEmpty)
        func tick(_ minute: Double, _ tz: String = "Europe/Amsterdam", _ offset: Int = 60) -> TickView {
            .init(atUtc: at(minute), tz: tz, offsetMin: offset)
        }
        let ticks = [
            tick(-1), tick(0), tick(60), tick(65, "Asia/Tokyo", 540), tick(70, "Asia/Tokyo", 540),
            tick(120, "Asia/Tokyo", 540), tick(270),
        ]
        #expect(tickPositions(day, ticks: ticks).map(\.visible) == [true, false, true, false, true])
        #expect(
            tickPositions(day, ticks: [tick(0), tick(5, "Asia/Tokyo", 540), tick(10, "Asia/Tokyo", 600)]).allSatisfy {
                $0.visible
            })
        var fold = day
        fold.startUtc = "2026-10-25T00:00Z"
        fold.endUtc = "2026-10-26T00:00Z"
        #expect(
            tickPositions(
                fold,
                ticks: [
                    .init(atUtc: fold.startUtc, tz: "Europe/Amsterdam", offsetMin: 120),
                    .init(atUtc: "2026-10-25T01:00Z", tz: "Europe/Amsterdam", offsetMin: 60),
                ]
            ).map(\.top) == [0, 40])
    }

    @Test func emittedLanesPresentationAndEmptyPlan() throws {
        let day = try sampleDay()
        var item = try block("transfer", 0, 60)
        let reasons = try fixture().timeline.blockReasons[0].lines
        let tick = TickView(atUtc: day.startUtc, tz: "Europe/Amsterdam", offsetMin: 60)
        let presentation = indexTimeline(
            .init(
                days: [.init(dayId: day.id, ticks: [tick])],
                blockReasons: [.init(blockId: item.id, lines: reasons)],
                transferWarnings: [.init(blockId: item.id, warningIndexes: [1, 0])]))
        let layout = layoutDay(day, blocks: [item], presentation: presentation)
        #expect(layout.placed[.sleep]![0].presentation == .init(reasons: reasons, warningIndexes: [1, 0]))
        #expect(layout.ticks[0].tick == tick && layout.ticks[0].top == 0)
        for (type, lane) in [
            (BlockType.movementBreak, Lane.travel), (.rest, .sleep), (.caffeineRoutine, .caffeine), (.note, .info),
        ] {
            item.type = type
            item.lane = lane
            let result = layoutDay(day, blocks: [item], presentation: emptyIndex())
            #expect(lane == .info ? result.markers[0].block == item : result.placed[lane]![0].block == item)
        }
        var plan = try fixture().plan
        plan.days = []
        plan.blocks = []
        #expect(layoutPlan(plan, timeline: .init(days: [], blockReasons: [], transferWarnings: [])).isEmpty)
        let original = try fixture().plan
        let intervals = summaryIntervals(original.days[2], blocks: original.blocks, type: .seekLight)
        #expect(
            intervals == [
                .init(start: planDate("2026-10-15T06:05:00Z"), end: planDate("2026-10-15T07:35:00Z"), tz: "Asia/Tokyo")
            ])
    }

    @Test func everyFixturePreservesLayoutAndResolvesCopy() async throws {
        let catalog = try await CopyCatalog.load()
        let formatter = CopyLineFormatter(catalog: try await CopyCatalog.load())
        for name in ["S1", "S2", "S3", "S4", "S5", "S6", "S6-RETURN-10N"] {
            let f = try fixture(name)
            let original = f.plan
            let types = Array(Set(f.plan.blocks.map(\.type)))
            let allHiddenLayouts = layoutPlan(f.plan, timeline: f.timeline, hidden: types)
            for hidden in [[], [.sleep, .note, .zoneChange], types] {
                let layouts = layoutPlan(f.plan, timeline: f.timeline, hidden: hidden)
                #expect(layouts.count == f.plan.days.count)
                for day in f.plan.days {
                    let layout = layouts[day.id]!
                    #expect(layout.height == planDate(day.endUtc).timeIntervalSince(planDate(day.startUtc)) / 3600 * 40)
                    for lane in timelineLanes {
                        let tiles = layout.placed[lane]!
                        let expected = f.plan.blocks.filter {
                            $0.isSupported && !isOptionalStep($0) && !hidden.contains($0.type) && $0.type != .zoneChange
                                && $0.lane == lane && planDate($0.startUtc) < planDate(day.endUtc)
                                && (planDate($0.endUtc) > planDate(day.startUtc)
                                    || ($0.startUtc == $0.endUtc && planDate($0.startUtc) >= planDate(day.startUtc)))
                        }
                        #expect(tiles.map { $0.block.id }.sorted() == expected.map(\.id).sorted())
                        for item in tiles {
                            #expect(item.top >= 0 && item.height > 0 && item.top + item.height <= layout.height + 1e-6)
                            #expect(item.col >= 0 && item.col < item.cols)
                            #expect(item.continuesBefore == (planDate(item.block.startUtc) < planDate(day.startUtc)))
                            #expect(item.continuesAfter == (planDate(item.block.endUtc) > planDate(day.endUtc)))
                            #expect(
                                item.presentation.reasons == f.timeline.blockReasons.first {
                                    $0.blockId == item.block.id
                                }?.lines ?? [])
                        }
                        for (i, a) in tiles.enumerated() {
                            for b in tiles.dropFirst(i + 1) where a.top + a.height > b.top {
                                #expect(a.cols == b.cols && a.col != b.col)
                            }
                        }
                    }
                    #expect(
                        layout.ticks
                            == tickPositions(day, ticks: f.timeline.days.first { $0.dayId == day.id }?.ticks ?? []))
                    let allHidden = allHiddenLayouts[day.id]!
                    #expect(
                        allHidden.placed.values.allSatisfy { $0.isEmpty } && allHidden.markers.isEmpty
                            && allHidden.changes.isEmpty)
                    #expect(allHidden.dividers == layout.dividers && allHidden.ticks == layout.ticks)
                }
            }
            #expect(
                f.plan == original
                    && withoutOptionalSteps(withoutOptionalSteps(original)) == withoutOptionalSteps(original))
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f.plan))
            func check(_ value: Any) {
                if let dict = value as? [String: Any] {
                    if let key = dict["key"] as? String, dict["args"] is [Any],
                        let data = try? JSONSerialization.data(withJSONObject: dict),
                        let line = try? JSONDecoder().decode(CopyLine.self, from: data)
                    {
                        #expect(catalog.contains(key))
                        for language in [Language.en, .nl] {
                            #expect(!formatter.format(line, options: .init(language: language)).isEmpty)
                        }
                    }
                    for item in dict.values { check(item) }
                } else if let list = value as? [Any] {
                    for item in list { check(item) }
                }
            }
            check(object)
        }
    }
}
