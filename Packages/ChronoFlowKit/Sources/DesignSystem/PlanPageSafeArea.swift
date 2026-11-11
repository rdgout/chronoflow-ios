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
    public static func horizontalBounds(_ frame: CGRect, leading: CGFloat = 0, trailing: CGFloat = 0) -> CGRect {
        CGRect(x: frame.minX + leading, y: 0, width: max(0, frame.width - leading - trailing), height: 1)
    }

    public static func horizontalInsets(frame: CGRect, safeBounds: CGRect) -> (left: CGFloat, right: CGFloat) {
        guard !frame.isEmpty, !safeBounds.isEmpty else { return (0, 0) }
        return (max(0, safeBounds.minX - frame.minX), max(0, frame.maxX - safeBounds.maxX))
    }
}

extension View {
    public func planPageSafeArea() -> some View {
        modifier(PlanPageSafeArea())
    }

    public func planPageRail() -> some View { modifier(PlanPageRail()) }
}

private struct PlanPageSafeArea: ViewModifier {
    @State private var bounds: CGRect?

    func body(content: Content) -> some View {
        content.environment(\.planPageSafeBounds, bounds)
            .onGeometryChange(for: CGRect.self) {
                // The frame already excludes the safe area. safeAreaInsets describe what lies outside it
                // (on Duo they still report the tab rail column, which a page can never extend into).
                PlanPageGeometry.horizontalBounds($0.frame(in: .global))
            } action: {
                bounds = $0
            }
    }
}

private struct PlanPageRail: ViewModifier {
    @Environment(\.planPageSafeBounds) private var safeBounds
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        let insets = safeBounds.map { PlanPageGeometry.horizontalInsets(frame: frame, safeBounds: $0) }
        content.padding(.leading, insets?.left ?? 0).padding(.trailing, insets?.right ?? 0)
            .onGeometryChange(for: CGRect.self) {
                // Vertical audit reflow must not feed another layout-state update.
                PlanPageGeometry.horizontalBounds($0.frame(in: .global))
            } action: {
                frame = $0
            }
    }
}
