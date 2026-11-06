import AppCore
import SwiftUI

private struct WelcomeNavigatorKey: EnvironmentKey {
    static var defaultValue: (any Navigator)? { nil }
}

extension EnvironmentValues {
    public var welcomeNavigator: (any Navigator)? {
        get { self[WelcomeNavigatorKey.self] }
        set { self[WelcomeNavigatorKey.self] = newValue }
    }
}
