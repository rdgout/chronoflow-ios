import AppCore

public enum MockWizardPrompts {
    public static func make(input: ApiTripInput, profile: JSONObject) -> [ApiReviewPrompt] {
        var prompts: [ApiReviewPrompt] = []
        func add(
            _ kind: PromptKind, _ key: String, _ fields: [String], profileTarget: Bool = false,
            required: Bool = false, journey: TripDirection? = nil, index: Int? = nil,
            options: [String] = [], shape: ReviewAnswerShape = .options, args: [CopyArgument] = []
        ) {
            let answer = Dictionary(
                uniqueKeysWithValues: fields.map { field in
                    let parts = field.split(separator: "_")
                    let camel =
                        String(parts.first ?? "")
                        + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
                    return (field, profileTarget ? profile[camel] ?? .null : .null)
                })
            prompts.append(
                ApiReviewPrompt(
                    id: [kind.rawValue, journey?.rawValue ?? "", index.map(String.init) ?? ""].joined(separator: ":"),
                    kind: kind, blocking: false, required: required, text: CopyLine(key: key, args: args),
                    scope: ApiReviewPromptScope(
                        journey: journey, legIndex: kind == .seatSide ? index : nil,
                        stayIndex: kind == .room || kind == .lateCheckOut ? index : nil),
                    target: profileTarget ? .profile : .trip, fields: fields, answer: answer,
                    shape: ApiReviewPromptShape(
                        kind: shape, options: options, min: kind == .cups ? 0 : nil, max: kind == .cups ? 20 : nil)))
        }
        for (direction, journey) in [(TripDirection.outbound, input.outbound), (.return, input.return)] {
            guard let journey else { continue }
            for (index, leg) in journey.legs.enumerated() {
                add(
                    .room, "Will you have a room in :place when you land, and from what time?",
                    ["stay.bed_available_mode", "stay.bed_available_from_local"], required: true, journey: direction,
                    index: index, options: ["arrival", "declared"],
                    args: [.standard(CopyArg(name: "place", kind: .place, value: .string(leg.toIata)))])
                add(
                    .seatSide, "On your flight to :place, a seat on the left side may let you see more daylight.",
                    ["seat_window"], journey: direction, index: index, options: ["left", "right"],
                    args: [.standard(CopyArg(name: "place", kind: .place, value: .string(leg.toIata)))])
                if direction == .outbound, input.return != nil {
                    add(
                        .lateCheckOut, "Can you check out late, or book a day room, in :place?",
                        ["stay.late_check_out_or_day_room"], journey: direction, index: index, shape: .boolean,
                        args: [.standard(CopyArg(name: "place", kind: .place, value: .string(leg.toIata)))])
                }
            }
        }
        add(
            .latestWake, "What is the latest you can wake up on the days before you leave?", ["latest_wake"],
            required: true, shape: .clockTime)
        add(
            .preDepartureBusyHours,
            "Which hours before you leave are you busy, so the plan keeps them free of light and naps?",
            ["pre_departure_busy_answered", "pre_departure_busy_intervals"], shape: .intervals)
        add(
            .freeDayTimes, "What time do you go to bed and wake up on free days?",
            ["free_day_status", "free_day_bed", "free_day_wake"], profileTarget: true,
            options: ["same_as_workdays", "declared"])
        if profile["excludeCaffeine"] != .bool(true) {
            add(
                .cups, "How many caffeinated drinks do you usually have in a day?",
                ["caffeine_habit", "cups_filter_coffee", "cups_tea", "cups_cola", "cups_energy_drink"],
                profileTarget: true, shape: .options)
        }
        add(
            .lightDevice,
            "Do you have a light box or light glasses? One gives the plan more room on days when daylight is hard to get.",
            ["light_device"], profileTarget: true, options: ["none", "box", "glasses"])
        add(
            .blueBlockers,
            "Do you have blue-blocking glasses with a rated protection? Tell us the rating if you know it.",
            ["blue_blockers", "blue_blocker_mdfd"], profileTarget: true, options: ["no", "rated", "unrated"])
        return prompts
    }
}
