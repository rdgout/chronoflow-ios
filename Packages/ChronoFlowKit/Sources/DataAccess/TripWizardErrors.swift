import AppCore
import Foundation

public enum TripWizardErrors {
    public static func map(_ failure: DataFailure, outboundCount: Int? = nil) -> DataFailure {
        guard case .validation(let fields, let status) = failure else { return failure }
        if fields["review_expired"] != nil { return .reviewExpired }
        if fields["credits"]?.key == "Not enough credits" { return .notEnoughCredits }
        if fields["review"]?.key == "Try saving again shortly." { return .saveCapacity }
        let mapped = fields.map { (path, message) in
            (outboundCount.map { journeyPath(path, outboundCount: $0) } ?? path, message)
        }
        let errors = Dictionary(mapped, uniquingKeysWith: { first, _ in first })
        if fields.keys.contains(where: { $0 == "profile" || $0.hasPrefix("profile.") }) {
            return .profileInvalid(fields: errors)
        }
        return .validation(fields: errors, status: status)
    }

    public static func journeyPath(_ path: String, outboundCount: Int) -> String {
        let parts = path.split(separator: ".").map(String.init)
        if parts.count >= 3, ["outbound", "return"].contains(parts[0]), parts[1] == "legs", let index = Int(parts[2]) {
            let flatIndex = index + (parts[0] == "return" ? outboundCount : 0)
            let stay = parts.count > 3 && parts[3] == "stay"
            return ([stay ? "stays" : "legs", String(flatIndex)] + parts.dropFirst(stay ? 4 : 3).map(camel)).joined(
                separator: ".")
        }
        if path == "override.use" { return "override.enabled" }
        let top = [
            "trip_end_kind": "end.kind", "trip_end_nights": "end.nights", "trip_end_check_out_date": "end.checkOutDate",
            "preparation_days": "preparation.days", "latest_wake": "preparation.latestWake",
            "pre_departure_busy_answered": "preparation.busyAnswered",
            "pre_departure_busy_intervals": "preparation.busyIntervals",
            "feasible_night_bed": "preparation.feasibleNightBed",
            "feasible_night_wake": "preparation.feasibleNightWake", "fast_delay_opt_in": "preparation.fastDelayOptIn",
        ]
        guard let first = parts.first else { return path }
        return ([top[first] ?? first] + parts.dropFirst().map(camel)).joined(separator: ".")
    }

    static func camel(_ key: String) -> String {
        let parts = key.split(separator: "_", omittingEmptySubsequences: false)
        return (parts.first.map(String.init) ?? "")
            + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
}
