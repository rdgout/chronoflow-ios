import AppCore
import Observation

public struct SettingsTimelineGroup: Sendable {
    public let title: String
    public let types: [String]
    public static var all: [Self] {
        [
            Self(title: "Sleep", types: ["sleep", "nap", "rest"]),
            Self(title: "Light", types: ["seek_light", "avoid_light", "light_ok", "light_neutral"]),
            Self(title: "Caffeine", types: ["caffeine_serving", "caffeine_routine", "caffeine_ok", "no_caffeine"]),
            Self(title: "Travel", types: ["flight", "layover", "transfer", "movement_break", "zone_change"]),
        ]
    }
}

@MainActor @Observable public final class SettingsPreferencesModel {
    public private(set) var value: JSONObject
    public private(set) var saved = false
    public private(set) var failure = false
    @ObservationIgnored private var edits: [String: JSONValue] = [:]
    @ObservationIgnored private let save: @MainActor (JSONObject) async throws -> Void
    @ObservationIgnored private var tail: Task<Void, Never>?
    public init(value: JSONObject, save: @escaping @MainActor (JSONObject) async throws -> Void) {
        self.value = value
        self.save = save
    }
    public func receive(_ value: JSONObject) {
        for (key, entry) in edits where value[key] == entry { edits[key] = nil }
        self.value = value
        for (key, entry) in edits { self.value[key] = entry }
    }
    public var hidden: [String] {
        if case .array(let values) = value["hiddenCategories"] { values.compactMap(\.string) } else { [] }
    }
    public func shown(_ group: SettingsTimelineGroup) -> Bool { !group.types.allSatisfy(hidden.contains) }
    public func setTimeFormat(_ format: String) async {
        guard ["12", "24"].contains(format) else {
            failure = true
            return
        }
        await change("timeFormat", .string(format), request: "time_format")
    }
    public func setShown(_ shown: Bool, group: SettingsTimelineGroup) async {
        var next = hidden.filter { !group.types.contains($0) }
        if !shown { next.append(contentsOf: group.types) }
        await change("hiddenCategories", .array(next.map(JSONValue.string)), request: "hidden_categories")
    }
    private func change(_ key: String, _ entry: JSONValue, request: String) async {
        value[key] = entry
        edits[key] = entry
        saved = false
        let previous = tail
        let task = Task { [weak self, save] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await save(JSONObject([request: entry]))
                self?.saved = true
                self?.failure = false
            } catch is CancellationError {
            } catch { self?.failure = true }
        }
        tail = task
        await task.value
    }
    deinit { tail?.cancel() }
}
