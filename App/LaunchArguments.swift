import AppCore
import DesignSystem
import Foundation
import Launch
import UIKit

struct LaunchArguments: Equatable {
    enum Mode: String { case ready, slow, welcome }
    let mode: Mode?
    let freezeAt: Duration?
    let readyAt: Duration
    let mainThreadStall: Duration?
    let reduceMotion: Bool

    init(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        func value(_ key: String) -> String? {
            guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        func milliseconds(_ key: String) -> Duration? {
            guard let raw = value(key), let number = Double(raw), number.isFinite, (0...60_000).contains(number)
            else { return nil }
            return .seconds(number / 1000)
        }
        mode = value("-cf.mode").flatMap(Mode.init(rawValue:))
        freezeAt = milliseconds("-cf.freezeAt")
        readyAt = milliseconds("-cf.readyAt") ?? .milliseconds(4600)
        mainThreadStall = milliseconds("-cf.mainThreadStall")
        reduceMotion = arguments.contains("-cf.reduceMotion")
    }

    static func fallbackRowHeight(compatibleWith traits: UITraitCollection) -> CGFloat {
        let base = CGFloat(Typography.welcomeWordmark.lineHeight!)
        guard traits.preferredContentSizeCategory != .large else { return base }
        return max(28, UIFontMetrics(forTextStyle: .title3).scaledValue(for: base, compatibleWith: traits))
    }

    func timeline(opening: LaunchTimeline, safeAreaInsets: MoonTarget.Insets, rowHeight: CGFloat = 28) -> LaunchTimeline
    {
        switch mode {
        case .ready: opening.withReadyExit(at: .milliseconds(1500))
        case .slow: opening.withStatus(at: .milliseconds(2000)).withReadyExit(at: readyAt)
        case .welcome:
            opening.withWelcomeExit(
                at: .milliseconds(1600), size: opening.size,
                moonTarget: MoonTarget.fallback(
                    size: opening.size,
                    safeAreaInsets: safeAreaInsets, rowHeight: rowHeight))
        case nil: opening
        }
    }
}
