import SwiftUI

private struct PlanContentMeasureKey: EnvironmentKey {
    static var defaultValue: (@MainActor (UUID, CGRect?) -> Void)? { nil }
}

extension EnvironmentValues {
    public var planContentMeasure: (@MainActor (UUID, CGRect?) -> Void)? {
        get { self[PlanContentMeasureKey.self] }
        set { self[PlanContentMeasureKey.self] = newValue }
    }
}

extension View {
    public func planContentBounds() -> some View { modifier(PlanContentBounds()) }
}

private struct PlanContentBounds: ViewModifier {
    @Environment(\.planContentMeasure) private var measure
    @State private var identity = UUID()

    @ViewBuilder func body(content: Content) -> some View {
        if let measure {
            content.onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                measure(identity, $0)
            }.onDisappear { measure(identity, nil) }
        } else {
            content
        }
    }
}
