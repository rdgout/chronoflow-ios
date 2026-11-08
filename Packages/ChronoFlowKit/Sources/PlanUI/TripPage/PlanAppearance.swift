import AppCore
import DesignSystem
import PlanCore
import SwiftUI

nonisolated struct PlanCategoryStyle {
    var fill: ColorToken
    var foreground: ColorToken
    var icon: String
    var pattern: Pattern?
    var dashed = false
    enum Pattern { case dots, hatch }

    init(_ type: BlockType) {
        switch type {
        case .sleep: self.init(fill: .catSleep, foreground: .catSleepFg, icon: "moon")
        case .nap: self.init(fill: .catSleep, foreground: .catSleepFg, icon: "bed.double", pattern: .dots)
        case .rest: self.init(fill: .catSleep, foreground: .catSleepFg, icon: "chair.lounge", pattern: .hatch)
        case .seekLight: self.init(fill: .catLight, foreground: .catLightFg, icon: "sun.max")
        case .avoidLight: self.init(fill: .catDark, foreground: .catDarkFg, icon: "eyeglasses", pattern: .hatch)
        case .lightOK:
            self.init(fill: .catModerate, foreground: .catModerateFg, icon: "cloud.sun", pattern: .dots, dashed: true)
        case .lightNeutral: self.init(fill: .catModerate, foreground: .catModerateFg, icon: "lamp.table")
        case .caffeineServing:
            self.init(fill: .catCaffeine, foreground: .catCaffeineFg, icon: "cup.and.saucer", pattern: .dots)
        case .caffeineRoutine:
            self.init(fill: .catCaffeine, foreground: .catCaffeineFg, icon: "cup.and.saucer", pattern: .hatch)
        case .caffeineOK: self.init(fill: .catCaffeine, foreground: .catCaffeineFg, icon: "cup.and.saucer")
        case .noCaffeine: self.init(fill: .card, foreground: .foreground, icon: "cup.and.saucer", dashed: true)
        case .flight: self.init(fill: .catTravel, foreground: .catTravelFg, icon: "airplane")
        case .layover: self.init(fill: .catTravel, foreground: .catTravelFg, icon: "timer", pattern: .hatch)
        case .transfer: self.init(fill: .catTravel, foreground: .catTravelFg, icon: "arrow.left.arrow.right")
        case .movementBreak: self.init(fill: .catTravel, foreground: .catTravelFg, icon: "figure.walk")
        case .zoneChange: self.init(fill: .catTravel, foreground: .catTravelFg, icon: "globe")
        default: self.init(fill: .card, foreground: .foreground, icon: "info.circle")
        }
    }

    private init(fill: ColorToken, foreground: ColorToken, icon: String, pattern: Pattern? = nil, dashed: Bool = false)
    {
        self.fill = fill
        self.foreground = foreground
        self.icon = icon
        self.pattern = pattern
        self.dashed = dashed
    }
}

struct PriorityTag: View {
    let label: String
    var body: some View {
        Text(verbatim: label).font(Typography.planCompactDate.font)
            .padding(.horizontal, PlanMetrics.tilePadding).padding(.vertical, PlanMetrics.border)
            .background(ColorToken.background.color.opacity(0.4), in: Capsule())
            .overlay(Capsule().strokeBorder(.foreground.opacity(0.4), lineWidth: PlanMetrics.border))
    }
}

struct PlanCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(PlanMetrics.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: PlanMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: PlanMetrics.cardRadius).strokeBorder(
                    ColorToken.border.color, lineWidth: PlanMetrics.border))
    }
}

nonisolated struct PlanPattern: Shape {
    var dots: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if dots {
            for y in stride(from: PlanMetrics.dotStep / 2, to: rect.height, by: PlanMetrics.dotStep) {
                for x in stride(from: PlanMetrics.dotStep / 2, to: rect.width, by: PlanMetrics.dotStep) {
                    path.addEllipse(
                        in: CGRect(x: x, y: y, width: PlanMetrics.dotRadius * 2, height: PlanMetrics.dotRadius * 2))
                }
            }
        } else {
            for x in stride(from: -rect.height, to: rect.width, by: PlanMetrics.patternStep) {
                path.move(to: CGPoint(x: x, y: rect.height))
                path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            }
        }
        return path
    }
}
