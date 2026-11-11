import SwiftUI

private struct PlanContentMeasureKey: EnvironmentKey {
    static var defaultValue: (@MainActor (UUID, String?, CGRect?) -> Void)? { nil }
}

extension EnvironmentValues {
    public var planContentMeasure: (@MainActor (UUID, String?, CGRect?) -> Void)? {
        get { self[PlanContentMeasureKey.self] }
        set { self[PlanContentMeasureKey.self] = newValue }
    }
}

extension View {
    public func planContentBounds(identifier: String? = nil) -> some View {
        modifier(PlanContentBounds(identifier: identifier))
    }
}

private struct PlanContentBounds: ViewModifier {
    let identifier: String?
    @Environment(\.planContentMeasure) private var measure
    @State private var identity = UUID()

    @ViewBuilder func body(content: Content) -> some View {
        if let measure {
            content.onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                measure(identity, identifier, $0)
            }.onDisappear { measure(identity, identifier, nil) }
        } else {
            content
        }
    }
}
