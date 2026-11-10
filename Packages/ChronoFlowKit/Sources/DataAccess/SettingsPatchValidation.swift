import AppCore

public enum SettingsPatchValidation {
    public static func validate(section: SettingsSection, patch: JSONObject) throws {
        let allowed: Set<String>
        switch section {
        case .preferences: allowed = ["time_format", "hidden_categories", "show_optional_items"]
        case .reminders: allowed = ["light", "avoid", "caffeine", "winddown", "lead_min"]
        case .bodyClock:
            allowed = ProfilePreferences.requestFields
        }
        for key in ["exclude_caffeine", "flight_movement_breaks"] where patch[key] != nil {
            guard case .bool = patch[key] else {
                throw DataFailure.validation(
                    fields: [key: FieldMessage(key: "Choose one of the available options.")], status: 422)
            }
        }
        guard !patch.fields.isEmpty, Set(patch.fields.keys).isSubset(of: allowed) else {
            throw DataFailure.validation(
                fields: ["form": FieldMessage(key: "This setting cannot be changed here.")], status: 422)
        }
    }
}
