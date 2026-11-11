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

    // Both inputs live in the rail's own space, so moving page and rail together changes neither.
    public static func railInsets(railWidth: CGFloat, container: CGRect?) -> (left: CGFloat, right: CGFloat) {
        guard let container, container.width > 0 else { return (0, 0) }
        return (max(0, container.minX), max(0, railWidth - container.maxX))
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

private let planPageSafeSpace = "plan.page.safe"

private struct PlanPageSafeArea: ViewModifier {
    @State private var bounds: CGRect?

    func body(content: Content) -> some View {
        content.environment(\.planPageSafeBounds, bounds)
            .coordinateSpace(.named(planPageSafeSpace))
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
    @State private var insets = RailInsets.zero

    func body(content: Content) -> some View {
        let safeBounds = safeBounds
        content.padding(.leading, insets.left).padding(.trailing, insets.right)
            .onGeometryChange(for: RailInsets.self) {
                // The page's safe area is read in the same snapshot, in the rail's own space, so a push or
                // pop translation never pairs a fresh frame with stale bounds.
                // The vertical axis is dropped: audit reflow must not feed another layout-state update.
                let result: (left: CGFloat, right: CGFloat)
                if let container = $0.bounds(of: .named(planPageSafeSpace)) {
                    result = PlanPageGeometry.railInsets(railWidth: $0.size.width, container: container)
                } else if let safeBounds {
                    result = PlanPageGeometry.horizontalInsets(
                        frame: PlanPageGeometry.horizontalBounds($0.frame(in: .global)), safeBounds: safeBounds)
                } else {
                    result = (0, 0)
                }
                return RailInsets(left: result.left, right: result.right)
            } action: {
                insets = $0
            }
    }
}

private nonisolated struct RailInsets: Equatable {
    let left: CGFloat
    let right: CGFloat
    static let zero = RailInsets(left: 0, right: 0)
}
