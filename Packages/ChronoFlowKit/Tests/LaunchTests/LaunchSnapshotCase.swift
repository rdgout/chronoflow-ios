import AppCore
import CoreGraphics
import Foundation
import Launch

nonisolated struct LaunchSnapshotCase {
    enum Mode: String { case ready, slow, welcome, reduceMotion }
    let mode: Mode
    let milliseconds: Int
    var name: String { "\(mode.rawValue)-\(milliseconds)" }

    static let all: [Self] =
        [0, 700, 1400, 1700, 1900].map { Self(mode: .ready, milliseconds: $0) }
        + [2600, 4900].map { Self(mode: .slow, milliseconds: $0) }
        + [1500, 1950, 2400].map { Self(mode: .welcome, milliseconds: $0) }
        + [Self(mode: .reduceMotion, milliseconds: 0)]

    func timeline(size: CGSize, safeInsets: MoonTarget.Insets) -> LaunchTimeline {
        let opening = LaunchTimeline.opening(size: size, reduceMotion: mode == .reduceMotion)
        switch mode {
        case .ready: return opening.withReadyExit(at: .milliseconds(1500))
        case .slow: return opening.withStatus(at: .milliseconds(2000)).withReadyExit(at: .milliseconds(4600))
        case .welcome:
            return opening.withWelcomeExit(
                at: .milliseconds(1600), size: size,
                moonTarget: MoonTarget.fallback(size: size, safeAreaInsets: safeInsets, rowHeight: 28))
        case .reduceMotion: return opening
        }
    }
}
