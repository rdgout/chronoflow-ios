import AppCore
import Foundation
import PlanCore

nonisolated public func tripDatesText(
    start: String, end: String?, language: Language, long: Bool = false
) -> String {
    let start = String(start.prefix(10))
    let end = String((end ?? start).prefix(10))
    let sameYear = start.prefix(4) == end.prefix(4)
    let sameMonth = start.prefix(7) == end.prefix(7)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language == .nl ? "nl_NL" : "en_GB")
    formatter.timeZone = .gmt
    func date(_ value: String, first: Bool = false) -> String {
        formatter.dateFormat = "d" + (first && sameMonth ? "" : long ? " MMMM" : " MMM") + (sameYear ? "" : " yyyy")
        return formatter.string(from: planDate(value)).replacingOccurrences(of: ".", with: "")
    }
    if start == end { return date(start) }
    let copy = PageCopy(language: language)
    return copy(long ? "%@ to %@" : "%@–%@", date(start, first: true), date(end))
}

nonisolated public func tripMetaText(
    start: String, end: String?, flights: [String], language: Language
) -> String {
    ([tripDatesText(start: start, end: end, language: language)]
        + flights.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        .joined(separator: " · ")
}
