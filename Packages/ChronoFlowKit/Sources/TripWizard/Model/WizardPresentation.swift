import AppCore
import Foundation

public enum WizardPresentation {
    public typealias Translate = (String, [String: String]) -> String

    public struct SourceChange: Codable, Sendable, Equatable {
        public enum Field: String, Codable, Sendable { case route, flight, returnFlight, sleep, extras }
        public var form: WizardForm
        public var fields: [Field]
        public var price: ApiReviewPrice?
        public var previousPrice: ApiReviewPrice?
        public init(form: WizardForm, fields: [Field], price: ApiReviewPrice?, previousPrice: ApiReviewPrice? = nil) {
            self.form = form
            self.fields = fields
            self.price = price
            self.previousPrice = previousPrice
        }
    }

    public static func sourceChangeSummary(
        _ change: SourceChange, review: ApiTripReview?, stayEnd: ApiStayEnd?, locale: Locale, t: Translate
    ) throws -> String? {
        guard let price = change.price else { return nil }
        let form = change.form
        var sentences: [String] = []
        for field in change.fields {
            switch field {
            case .route:
                sentences.append(
                    t(
                        "On another device: the route changed to {{from}} → {{to}}.",
                        [
                            "from": form.legs.first?.fromIata ?? "",
                            "to": form.legs.prefix(form.returnBoundary).last?.toIata ?? "",
                        ]))
            case .flight:
                sentences.append(
                    t(
                        "On another device: the outbound flight changed to {{flight}}.",
                        ["flight": flightSummary(form, locale: locale, t: t)]))
            case .returnFlight:
                if form.end.kind == "return_legs", form.legs.indices.contains(form.returnBoundary),
                    let date = WizardDateTime.date(form.legs[form.returnBoundary].departLocal)
                {
                    sentences.append(
                        t(
                            "On another device: the return flight moved to {{date}}.",
                            ["date": WizardDateTime.format(date, template: "EEE d MMM", locale: locale)]))
                } else {
                    sentences.append(
                        t(
                            "On another device: the trip end changed to {{end}}.",
                            ["end": returnSummary(form, stayEnd: stayEnd, locale: locale, t: t)]))
                }
            case .sleep:
                sentences.append(
                    form.override.enabled
                        ? t(
                            "On another device: the sleep times changed to {{times}}.",
                            ["times": (form.override.habitualBed ?? "") + "–" + (form.override.habitualWake ?? "")])
                        : t("On another device: the trip now uses your usual sleep times.", [:]))
            case .extras:
                let extras = try extrasSummary(
                    form, review: review, input: form.reviewInput(identity: nil), locale: locale, t: t)
                sentences.append(t("On another device: the extras changed to {{extras}}.", ["extras": extras]))
            }
        }
        let text = price.cost == 0 ? t("Free", [:]) : t("{{count}} credits", ["count": String(price.cost)])
        sentences.append(
            t(
                change.previousPrice?.cost == price.cost
                    ? "The price is still {{price}}." : "The price is now {{price}}.", ["price": text]))
        return sentences.joined(separator: " ")
    }

    public static func promptKey(_ prompt: ApiReviewPrompt) -> String {
        [
            prompt.kind.rawValue, prompt.text.key, prompt.scope.stayIndex.map(String.init) ?? "",
            prompt.scope.legIndex.map(String.init) ?? "",
        ].joined(separator: ":")
    }

    public static func promptAnswers(_ prompt: ApiReviewPrompt, input: ApiTripReviewInput) throws -> [String: JSONValue]
    {
        let root = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(input.input))
        let journey = prompt.scope.journey == .return ? input.input.return : input.input.outbound
        let index = prompt.scope.legIndex ?? prompt.scope.stayIndex ?? 0
        let leg = journey.flatMap { $0.legs.indices.contains(index) ? $0.legs[index] : nil }
        var values = root.fields
        if let leg {
            let object = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(leg))
            values.merge(object.fields) { _, last in last }
        }
        return Dictionary(
            uniqueKeysWithValues: prompt.fields.map { field in
                let value = prompt.target == .profile ? input.profile?[field] : pathValue(.object(values), path: field)
                return (field, value == nil || value == .null ? prompt.answer[field] ?? .null : value!)
            })
    }

    public static func promptAnswerText(
        _ prompt: ApiReviewPrompt, input: ApiTripReviewInput, locale: Locale, t: Translate
    ) throws -> String {
        let answers = try promptAnswers(prompt, input: input)
        guard let first = prompt.fields.first, let value = answers[first], value != .null else { return t("Add", [:]) }
        if prompt.kind.rawValue == "pre_departure_busy_hours" {
            let count: Int
            if case .array(let rows) = answers["pre_departure_busy_intervals"] { count = rows.count } else { count = 0 }
            return t("{{count}} time ranges", ["count": String(count)])
        }
        if prompt.kind.rawValue == "cups" {
            if value == .string("non_user") { return t("None", [:]) }
            let count = ["cups_filter_coffee", "cups_tea", "cups_cola", "cups_energy_drink"].reduce(Decimal.zero) {
                sum, field in
                if case .number(let number) = answers[field] { sum + number } else { sum }
            }
            return t("{{count}} a day", ["count": NSDecimalNumber(decimal: count).stringValue])
        }
        if prompt.kind.rawValue == "free_day_times" {
            if value == .string("same_as_workdays") { return t("Same as work days", [:]) }
            if let bed = answers["free_day_bed"]?.string, let wake = answers["free_day_wake"]?.string {
                return bed + "–" + wake
            }
            return t("Different times", [:])
        }
        if prompt.kind.rawValue == "room" {
            return value == .string("arrival")
                ? t("When I land", [:])
                : t(
                    "From {{time}}",
                    ["time": String((answers["stay.bed_available_from_local"]?.string ?? "").suffix(5))])
        }
        if prompt.kind == .blueBlockers, value == .string("rated") {
            let number: Decimal?
            if case .number(let value) = answers["blue_blocker_mdfd"] {
                number = value
            } else {
                number = answers["blue_blocker_mdfd"]?.string.flatMap {
                    Decimal(
                        string: $0.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
                }
            }
            let formatter = NumberFormatter()
            formatter.locale = locale
            return t(
                "Rated {{rating}}",
                ["rating": number.flatMap { formatter.string(from: NSDecimalNumber(decimal: $0)) } ?? ""])
        }
        if case .bool(let value) = value { return t(value ? "Yes" : "No", [:]) }
        let names = [
            "left": "Window left", "right": "Window right", "none": "None", "box": "Light box",
            "glasses": "Light glasses", "no": "No", "unrated": "Yes, no rating",
        ]
        let raw: String
        if case .number(let number) = value {
            raw = NSDecimalNumber(decimal: number).stringValue
        } else {
            raw = value.string ?? String(describing: value)
        }
        return names[raw].map { t($0, [:]) } ?? raw
    }

    public static func flightSummary(_ form: WizardForm, home: Bool = false, locale: Locale, t: Translate) -> String {
        let legs = home ? Array(form.legs.dropFirst(form.returnBoundary)) : Array(form.legs.prefix(form.returnBoundary))
        guard let first = legs.first, let last = legs.last, let departure = WizardDateTime.date(first.departLocal),
            let arrival = WizardDateTime.date(last.arriveLocal)
        else { return "" }
        let start =
            WizardDateTime.format(departure, template: "EEE d MMM", locale: locale) + " " + first.departLocal.suffix(5)
        let end =
            (first.departLocal.prefix(10) == last.arriveLocal.prefix(10)
                ? "" : WizardDateTime.format(arrival, template: "EEE", locale: locale) + " ")
            + last.arriveLocal.suffix(5)
        let flight = start + " → " + end
        return legs.count > 1
            ? t(
                "{{flight}} · via {{airports}}",
                ["flight": flight, "airports": legs.dropLast().map(\.toIata).joined(separator: ", ")]) : flight
    }

    public static func extrasSummary(
        _ form: WizardForm, review: ApiTripReview?, input: ApiTripReviewInput, locale: Locale, t: Translate
    ) throws -> String {
        var answered = 0
        for prompt in review?.prompts ?? [] where !prompt.blocking {
            if try promptAnswerText(prompt, input: input, locale: locale, t: t) != t("Add", [:]) { answered += 1 }
        }
        let prep =
            form.preparation.days == 0
            ? t("No prep days", [:]) : t("{{count}} days prep", ["count": String(form.preparation.days)])
        return answered > 0 ? t("{{count}} answered", ["count": String(answered)]) + " · " + prep : prep
    }

    public static func returnSummary(_ form: WizardForm, stayEnd: ApiStayEnd?, locale: Locale, t: Translate) -> String {
        if form.end.kind == "return_legs" { return flightSummary(form, home: true, locale: locale, t: t) }
        let nights = t("{{count}} nights", ["count": String(form.end.nights ?? 0)])
        let end =
            form.end.kind == "check_out"
            ? form.end.checkOutDate : form.end.kind == "nights" ? stayEnd?.checkOutLocalDate : nil
        guard let end, let date = WizardDateTime.date(end + "T12:00") else {
            return form.end.kind == "nights" ? nights : t("One way", [:])
        }
        let text = WizardDateTime.format(date, template: "EEE d MMM", locale: locale).replacingOccurrences(
            of: ",", with: "")
        return form.end.kind == "nights"
            ? t("{{nights}} · until {{date}}", ["nights": nights, "date": text])
            : t("Check-out · {{date}}", ["date": text])
    }

    public static func planDateSummary(_ form: WizardForm, summary: ApiReviewSummary?, locale: Locale, t: Translate)
        -> String
    {
        guard let summary, let start = WizardDateTime.parseInstant(summary.planStartUtc),
            let end = WizardDateTime.date(summary.planEndDate + "T12:00"),
            let zone = TimeZone(identifier: summary.planStartZone)
        else { return "" }
        var calendar = WizardDateTime.calendar
        calendar.timeZone = zone
        let year = calendar.component(.year, from: start) != WizardDateTime.calendar.component(.year, from: end)
        let template = year ? "EEE d MMM y" : "EEE d MMM"
        let range =
            WizardDateTime.format(start, template: template, locale: locale, zone: zone) + " – "
            + WizardDateTime.format(end, template: template, locale: locale)
        if form.end.kind == "check_out" { return range }
        let kind =
            form.end.kind == "nights"
            ? t("{{count}} nights", ["count": String(form.end.nights ?? 0)])
            : t(form.end.kind == "return_legs" ? "return" : "one way", [:])
        return range + " · " + kind
    }

    public static func planDayCount(_ summary: ApiReviewSummary?) -> Int? {
        guard let summary, let start = WizardDateTime.parseInstant(summary.planStartUtc),
            let zone = TimeZone(identifier: summary.planStartZone),
            let end = WizardDateTime.date(summary.planEndDate + "T12:00")
        else { return nil }
        var calendar = WizardDateTime.calendar
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        guard let wall = WizardDateTime.calendar.date(from: parts) else { return nil }
        return WizardDateTime.calendar.dateComponents(
            [.day], from: wall, to: WizardDateTime.calendar.startOfDay(for: end)
        ).day.map { $0 + 1 }
    }

    public static func promptFieldError(_ prompt: ApiReviewPrompt, form: WizardForm, errors: [String: FieldMessage])
        -> FieldMessage?
    {
        let paths = prompt.fields.map { field in
            let raw =
                prompt.target == .profile
                ? "profile." + field
                : field == "latest_wake" || field.hasPrefix("pre_departure_")
                    ? field
                    : "\(prompt.scope.journey?.rawValue ?? "outbound").legs.\(prompt.scope.legIndex ?? prompt.scope.stayIndex ?? 0).\(field)"
            return WizardJourney.errorPath(raw, form: form)
        }
        return errors.sorted { $0.key < $1.key }.first { path, _ in
            paths.contains { path == $0 || path.hasPrefix($0 + ".") }
        }?.value
    }

    private static func pathValue(_ root: JSONValue, path: String) -> JSONValue? {
        path.split(separator: ".").reduce(Optional(root)) { value, key in
            if case .array(let array) = value, let index = Int(key), array.indices.contains(index) {
                return array[index]
            }
            return value?.object?[String(key)]
        }
    }
}
