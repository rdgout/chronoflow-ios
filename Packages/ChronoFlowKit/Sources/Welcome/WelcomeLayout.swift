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
