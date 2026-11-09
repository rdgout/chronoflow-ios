import AppCore
import Foundation
import PlanCore
import Testing

@testable import Reminders

private struct Corpus: Decodable {
    var cases: [Vector]
    struct Vector: Decodable {
        var test: String
        var blocks: [ParityBlock]
        var settings: ReminderSettings
        var now: Date
        var options: Options
        var expected: [ReminderDraft]
    }
    struct Options: Decodable {
        var coalesceMinutes: Int?
        var dailyCap: Int?
        var expiryGraceMinutes: Int?
        var sentMemberKeys: [String: Bool]?
        var sentCountsByDay: [String: Int]?
        struct Timeline: Decodable { var blockReasons: [BlockReasonTagsView] }
        var timeline: Timeline?
    }
}

@Suite struct ReminderSelectionTests {
    @Test func allRNSelectionVectors() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return planDate(text)
        }
        let url = Bundle.module.url(forResource: "selection", withExtension: "json", subdirectory: "Fixtures")!
        let corpus = try decoder.decode(Corpus.self, from: Data(contentsOf: url))
        #expect(corpus.cases.count == 110)
        for vector in corpus.cases {
            var options = ReminderSelectionOptions()
            options.coalesceMinutes = vector.options.coalesceMinutes ?? 15
            options.dailyCap = vector.options.dailyCap ?? 6
            options.expiryGraceMinutes = vector.options.expiryGraceMinutes ?? 20
            options.sentMemberKeys = Set((vector.options.sentMemberKeys ?? [:]).filter(\.value).map(\.key))
            options.sentCountsByDay = vector.options.sentCountsByDay ?? [:]
            if let timeline = vector.options.timeline {
                options.timeline = TimelinePresentationView(
                    days: [], blockReasons: timeline.blockReasons, transferWarnings: [])
            }
            #expect(
                reminderDrafts(
                    try vector.blocks.map { try $0.value() }, settings: vector.settings, now: vector.now,
                    options: options) == vector.expected, "\(vector.test)")
        }
    }

}

private struct ParityBlock: Decodable {
    var id: String
    var lane: Lane
    var type: BlockType
    var startUtc: String
    var endUtc: String
    var displayTz: String
    var priority: Priority
    var text: CopyLine
    var params: JSONValue
    var actionable: Bool
    var checkKey: CheckKeyView?
    func value() throws -> BlockView {
        // RN's synthetic excluded blocks omit required presenter fields; selection only reads sleep params.
        let typed: BlockParams =
            type == .sleep
            ? .sleep(try JSONDecoder().decode(SleepParamsView.self, from: JSONEncoder().encode(params)))
            : .unknown(params)
        return BlockView(
            id: id, lane: lane, type: type, startUtc: startUtc, endUtc: endUtc, displayTz: displayTz,
            priority: priority, text: text, params: typed, actionable: actionable, checkKey: checkKey)
    }
}
