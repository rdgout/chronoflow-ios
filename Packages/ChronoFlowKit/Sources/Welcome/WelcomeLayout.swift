import AppCore
import DesignSystem
import SwiftUI

enum WelcomeElement: String, CaseIterable { case brand, eyebrow, headline, copy, plan, signIn }

private struct LayoutObserverKey: EnvironmentKey {
    static var defaultValue: (@MainActor (WelcomeElement, CGRect) -> Void)? { nil }
}

extension EnvironmentValues {
    var welcomeLayoutObserver: (@MainActor (WelcomeElement, CGRect) -> Void)? {
        get { self[LayoutObserverKey.self] }
        set { self[LayoutObserverKey.self] = newValue }
    }
}

extension View {
    func reportWelcomeFrame(_ element: WelcomeElement) -> some View {
        modifier(FrameReporter(element: element))
    }
}

private struct FrameReporter: ViewModifier {
    @Environment(\.welcomeLayoutObserver) private var observer
    let element: WelcomeElement

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            observer?(element, $0)
        }
    }
}

nonisolated public struct WelcomeGeometry: Sendable, Equatable {
    public let content: CGRect
    public let top: CGFloat
    public let bottom: CGFloat
    public let leading: CGFloat
    public let trailing: CGFloat

    public init(size: CGSize, insets: MoonTarget.Insets) {
        top = max(insets.top + WelcomeTokens.groupGap, WelcomeTokens.topPadding)
        bottom = max(insets.bottom, WelcomeTokens.bottomPadding)
        leading = insets.left + WelcomeTokens.gutter
        trailing = insets.right + WelcomeTokens.gutter
        content = CGRect(
            x: leading, y: top, width: max(0, size.width - leading - trailing),
            height: max(0, size.height - top - bottom))
    }

    public func groups(headingHeight: CGFloat, actionsHeight: CGFloat) -> (heading: CGRect, actions: CGRect) {
        let heading = CGRect(origin: content.origin, size: CGSize(width: content.width, height: headingHeight))
        let actions = CGRect(
            x: content.minX, y: max(heading.maxY + WelcomeTokens.gutter, content.maxY - actionsHeight),
            width: content.width, height: actionsHeight)
        return (heading, actions)
    }
}
