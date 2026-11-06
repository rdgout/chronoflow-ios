import AppCore
import SwiftUI

private struct MoonAnchorKey: EnvironmentKey {
    static var defaultValue: MoonAnchorStore? { nil }
}

extension EnvironmentValues {
    public var moonAnchorStore: MoonAnchorStore? {
        get { self[MoonAnchorKey.self] }
        set { self[MoonAnchorKey.self] = newValue }
    }
}
