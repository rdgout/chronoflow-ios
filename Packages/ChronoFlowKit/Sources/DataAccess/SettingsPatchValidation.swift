import AppCore

public enum SettingsPatchValidation {
    public static func validate(section: SettingsSection, patch: JSONObject) throws {
        let allowed: Set<String>
        switch section {
        case .preferences: allowed = ["time_format", "hidden_categories", "show_optional_items"]
        case .reminders: allowed = ["light", "avoid", "caffeine", "winddown", "lead_min"]
        case .bodyClock:
            allowed = [
                "habitual_bed", "habitual_wake", "free_day_status", "free_day_bed", "free_day_wake", "chronotype",
                "age_band", "shift_work", "bipolar", "eye_disease", "pregnancy", "caffeine_ruled_out", "vte",
                "sleep_phase_disorder", "caffeine_habit", "cups_filter_coffee", "cups_tea", "cups_cola",
                "cups_energy_drink", "caffeine_sensitive", "caffeine_non_user_opt_in", "oral_contraception",
                "light_device", "blue_blockers", "blue_blocker_mdfd",
            ]
        }
        guard !patch.fields.isEmpty, Set(patch.fields.keys).isSubset(of: allowed) else {
            throw DataFailure.validation(
                fields: ["form": FieldMessage(key: "This setting cannot be changed here.")], status: 422)
        }
    }
}
