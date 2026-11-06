import SwiftUI

private struct ForcedReduceMotionKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    public var forcesReduceMotion: Bool {
        get { self[ForcedReduceMotionKey.self] }
        set { self[ForcedReduceMotionKey.self] = newValue }
    }
}

public struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forcesReduceMotion) private var forcesReduceMotion

    nonisolated public struct Values: Equatable, Sendable {
        public let scale: Double
        public let opacity: Double
        public let duration: Double
    }

    public init() {}

    nonisolated public static func values(isPressed: Bool, reduceMotion: Bool) -> Values {
        Values(
            scale: isPressed && !reduceMotion ? PressTokens.scale : 1,
            opacity: isPressed ? PressTokens.opacity : 1,
            duration: reduceMotion ? 0 : PressTokens.duration)
    }

    public func makeBody(configuration: Configuration) -> some View {
        let reduceMotion = reduceMotion || forcesReduceMotion
        let values = Self.values(isPressed: configuration.isPressed, reduceMotion: reduceMotion)
        let curve = PressTokens.curve
        configuration.label
            .scaleEffect(values.scale)
            .opacity(values.opacity)
            .animation(
                reduceMotion ? nil : .timingCurve(curve[0], curve[1], curve[2], curve[3], duration: values.duration),
                value: configuration.isPressed)
    }
}
