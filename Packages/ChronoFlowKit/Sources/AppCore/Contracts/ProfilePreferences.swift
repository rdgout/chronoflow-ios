import Foundation

public enum ProfilePreferences {
    public static var requestFields: Set<String> {
        [
            "habitual_bed", "habitual_wake", "free_day_status", "free_day_bed", "free_day_wake", "chronotype",
            "age_band", "shift_work", "exclude_caffeine", "flight_movement_breaks", "caffeine_habit",
            "cups_filter_coffee", "cups_tea", "cups_cola", "cups_energy_drink", "caffeine_sensitive",
            "caffeine_non_user_opt_in", "light_device", "blue_blockers", "blue_blocker_mdfd",
        ]
    }

    public static func camel(_ key: String) -> String {
        let parts = key.split(separator: "_")
        return String(parts.first ?? "") + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    public static func bodyClock(_ value: JSONObject) -> JSONObject {
        let allowed = Set(requestFields.map(camel))
        var result = JSONObject(value.fields.filter { allowed.contains($0.key) })
        result["excludeCaffeine"] = .bool(
            value["excludeCaffeine"] == .bool(true)
                || (value["excludeCaffeine"] == nil && value["caffeineRuledOut"] == .bool(true)))
        result["flightMovementBreaks"] = .bool(value["flightMovementBreaks"] == .bool(true))
        result["invalidDrafts"] = .object(
            (value["invalidDrafts"]?.object ?? [:]).filter { requestFields.contains($0.key) })
        return result
    }

    public static func request(_ value: JSONObject) -> JSONObject {
        var result = JSONObject(promptAnswers(value.fields).filter { requestFields.contains($0.key) })
        for key in ["exclude_caffeine", "flight_movement_breaks"] where result[key] != nil {
            result[key] = .bool(result[key] == .bool(true))
        }
        return result
    }

    public static func promptAnswers(_ values: [String: JSONValue]) -> [String: JSONValue] {
        cleanLegacyValue(.object(values))?.object ?? [:]
    }

    public static func reviewPrompts(_ prompts: [ApiReviewPrompt]) -> [ApiReviewPrompt] {
        prompts.filter(isSupported).map {
            var prompt = $0
            prompt.answer = promptAnswers(prompt.answer)
            return prompt
        }
    }

    public static func isSupported(_ prompt: ApiReviewPrompt) -> Bool {
        if prompt.kind == .screening { return prompt.target == .profile && prompt.fields == ["shift_work"] }
        if prompt.kind == .ageBand { return prompt.target == .profile && prompt.fields == ["age_band"] }
        return prompt.target != .profile || Set(prompt.fields).isSubset(of: requestFields)
    }

    public static func isSupported(_ prompt: PromptView) -> Bool {
        prompt.kind != .screening || prompt.question == .shiftWork
    }

    public static func readiness(_ value: JSONObject, bodyClock: JSONObject) -> JSONObject {
        var result = JSONObject()
        let missing: [JSONValue] = [
            ("ageBand", JSONValue.null), ("shiftWork", .string("shift_work")),
        ].compactMap { key, question in
            guard bodyClock[key] == nil || bodyClock[key] == .null || bodyClock[key] == .string("unanswered") else {
                return nil
            }
            return .object(["question": question])
        }
        let underAge = bodyClock["ageBand"] == .string("under_18")
        let shiftWork = bodyClock["shiftWork"] == .bool(true)
        let excluded = underAge || shiftWork
        let adjustments = adjustmentKeys(bodyClock).map { JSONValue.object(["key": .string($0), "args": .array([])]) }
        let invalid: [JSONValue]
        if case .array(let values) = value["invalidSections"] { invalid = values } else { invalid = [] }
        result["invalidSections"] = .array(invalid)
        result["variant"] = .string(
            excluded
                ? "excluded"
                : !missing.isEmpty || !invalid.isEmpty
                    ? "needs-answers"
                    : adjustments.isEmpty ? "ready" : "adjusted")
        result["missing"] = .array(excluded ? [] : missing)
        result["exclusionTarget"] =
            excluded
            ? .object(["question": underAge ? .null : .string("shift_work")]) : .null
        result["exclusions"] = .array(
            excluded
                ? [
                    .object([
                        "key": .string(
                            underAge
                                ? "This plan is not available for travellers under 18."
                                : "This plan is not available if, in the past 14 days, you have worked night or rotating shifts or had a very irregular sleep schedule."
                        ),
                        "args": .array([]),
                    ])
                ] : [])
        result["adjustments"] = .array(adjustments)
        return result
    }

    private static var retiredFields: Set<String> {
        [
            "bipolar", "eye_disease", "eyeDisease", "pregnancy", "vte", "sleep_phase_disorder", "sleepPhaseDisorder",
            "oral_contraception", "oralContraception", "caffeine_ruled_out", "caffeineRuledOut",
        ]
    }

    public static func containsRetiredValues(_ json: String) -> Bool {
        retiredFields.contains { json.contains("\"" + $0 + "\"") }
            || json.contains("Answer the health questions to get your plan.")
    }

    public static func cleanLegacyJSON(_ data: Data) throws -> Data {
        guard containsRetiredValues(String(decoding: data, as: UTF8.self)) else { return data }
        let original = try JSONDecoder().decode(JSONValue.self, from: data)
        let cleaned = cleanLegacyValue(original) ?? .null
        return cleaned == original ? data : try JSONEncoder().encode(cleaned)
    }

    private static func cleanLegacyValue(_ value: JSONValue) -> JSONValue? {
        switch value {
        case .object(let fields):
            if let question = fields["question"]?.string, retiredFields.contains(question) { return nil }
            if fields["kind"] == .string("screening"), case .array(let keys) = fields["fields"],
                keys.contains(where: { retiredFields.contains($0.string ?? "") })
            {
                return nil
            }
            var result: [String: JSONValue] = [:]
            for (key, entry) in fields where !retiredFields.contains(key) {
                result[key] = cleanLegacyValue(entry)
            }
            if result["key"] == .string("Answer the health questions to get your plan.") {
                result["key"] = .string("Answer the questions to get your plan.")
            }
            return .object(result)
        case .array(let values): return .array(values.compactMap(cleanLegacyValue))
        default: return value
        }
    }

    private static func adjustmentKeys(_ body: JSONObject) -> [String] {
        var keys: [String] = []
        if body["excludeCaffeine"] == .bool(true) { keys.append("No caffeine anywhere in your plan.") }
        if body["flightMovementBreaks"] == .bool(true) {
            keys.append("Regular movement breaks on long flights, with shorter in-flight sleep stretches.")
        }
        if body["ageBand"] == .string("65_plus") {
            keys.append("Your plan takes your age range into account in its timing.")
        }
        return keys
    }
}
