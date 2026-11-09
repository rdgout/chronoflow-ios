import Foundation
import UIKit

@MainActor enum SettingsPreferenceStore {
    static func make() -> UserDefaults {
        #if DEBUG
            if (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true,
                let raw = ProcessInfo.processInfo.environment["CF_AUTH_TEST_ID"], let id = UUID(uuidString: raw),
                let defaults = UserDefaults(suiteName: "ChronoFlow.Settings.UITest.\(id.uuidString)")
            {
                return defaults
            }
        #endif
        return .standard
    }
}
