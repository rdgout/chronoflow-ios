import AppCore
import DesignSystem
import SwiftUI

private struct LaunchIntroKey: EnvironmentKey {
    static var defaultValue: LaunchIntro? { nil }
}

extension EnvironmentValues {
    public var launchIntro: LaunchIntro? {
        get { self[LaunchIntroKey.self] }
        set { self[LaunchIntroKey.self] = newValue }
    }
}

public struct IntroItem: ViewModifier {
    @Environment(\.launchIntro) private var intro
    @State private var landed = false
    private let index: Int

    public init(index: Int) { self.index = index }

    public func body(content: Content) -> some View {
        if let intro, let time = intro.frozenTime {
            content
                .opacity(intro.progress(for: index, at: time))
                .offset(y: WelcomeTokens.introRise * (1 - intro.progress(for: index, at: time)))
                .transaction {
                    $0.animation = nil
                    $0.disablesAnimations = true
                }
        } else {
            content
                .opacity(intro == nil || landed ? 1 : 0)
                .offset(y: intro == nil || landed ? 0 : WelcomeTokens.introRise)
                .task(id: intro.map(ObjectIdentifier.init)) {
                    guard let intro else { return }
                    if intro.progress(for: index, at: intro.clock.now) == 1 {
                        landed = true
                    } else {
                        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45).delay(intro.delay(for: index))) {
                            landed = true
                        }
                    }
                }
        }
    }
}
