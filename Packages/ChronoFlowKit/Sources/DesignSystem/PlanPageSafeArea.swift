import SwiftUI

private struct PlanPageSafeBoundsKey: EnvironmentKey {
    static var defaultValue: CGRect? { nil }
}

extension EnvironmentValues {
    public var planPageSafeBounds: CGRect? {
        get { self[PlanPageSafeBoundsKey.self] }
        set { self[PlanPageSafeBoundsKey.self] = newValue }
    }
}

public nonisolated enum PlanPageGeometry {
    public static func horizontalInsets(frame: CGRect, safeBounds: CGRect) -> (left: CGFloat, right: CGFloat) {
        guard !frame.isEmpty, !safeBounds.isEmpty else { return (0, 0) }
        return (max(0, safeBounds.minX - frame.minX), max(0, frame.maxX - safeBounds.maxX))
    }
}

extension View {
    public func planPageSafeArea() -> some View {
        GeometryReader { geometry in
            // Capture the safe proposal before native navigation consumes the side insets.
            self.environment(\.planPageSafeBounds, geometry.frame(in: .global))
        }
    }

    public func planPageRail() -> some View { modifier(PlanPageRail()) }
}

private struct PlanPageRail: ViewModifier {
    @Environment(\.planPageSafeBounds) private var safeBounds
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        let insets = safeBounds.map { PlanPageGeometry.horizontalInsets(frame: frame, safeBounds: $0) }
        content.padding(.leading, insets?.left ?? 0).padding(.trailing, insets?.right ?? 0)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                frame = $0
            }
    }
}
