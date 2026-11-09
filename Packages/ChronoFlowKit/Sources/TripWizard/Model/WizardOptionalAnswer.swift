import AppCore
import Foundation

public enum WizardOptionalAnswer {
    public static var drinkFields: [String] { ["cups_filter_coffee", "cups_tea", "cups_cola", "cups_energy_drink"] }
    public static func error(_ prompt: ApiReviewPrompt, values: [String: JSONValue]) -> String? {
        if prompt.kind == .cups, values["caffeine_habit"] != .string("non_user"),
            !drinkFields.contains(where: { field in
                if case .number(let count) = values[field] { return count > 0 }
                return false
            })
        {
            return "Add at least one drink to save this answer."
        }
        if prompt.kind == .blueBlockers, values["blue_blockers"] == .string("rated") {
            let text: String
            if case .number(let rating) = values["blue_blocker_mdfd"] {
                text = NSDecimalNumber(decimal: rating).stringValue
            } else {
                text = values["blue_blocker_mdfd"]?.string ?? ""
            }
            guard let rating = Double(text.replacingOccurrences(of: ",", with: ".")), rating.isFinite,
                (0.1...9.9).contains(rating)
            else { return "Enter a rating between 0.1 and 9.9." }
        }
        if prompt.kind == .freeDayTimes, values["free_day_status"] == .string("declared"),
            !WizardDateTime.isTime(values["free_day_bed"]?.string)
                || !WizardDateTime.isTime(values["free_day_wake"]?.string)
        {
            return "Check your bedtime and wake-up time."
        }
        return nil
    }
}
