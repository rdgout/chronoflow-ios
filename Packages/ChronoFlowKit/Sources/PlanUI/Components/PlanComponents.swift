#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    public struct CategorySwatch: View {
        public let type: BlockType
        public init(_ type: BlockType) { self.type = type }
        public var body: some View {
            Image(systemName: symbol).font(Typography.screenBodyLg.font)
                .frame(width: PlanUITokens.space8, height: PlanUITokens.space8)
                .background { pattern }.background(
                    fill.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radiusLg)
                )
                .overlay {
                    if [.lightOK, .noCaffeine, .note].contains(type) {
                        RoundedRectangle(cornerRadius: PlanUITokens.radiusLg)
                            .strokeBorder(
                                foreground.color,
                                style: StrokeStyle(lineWidth: AuthTokens.borderWidth, dash: [PlanUITokens.space1]))
                    }
                }
                .foregroundStyle(foreground.color).accessibilityHidden(true)
        }
        private var pattern: some View {
            Canvas { context, size in
                if [.nap, .lightOK, .caffeineServing].contains(type) {
                    for x in stride(from: CGFloat.zero, through: size.width, by: PlanUITokens.patternDotSpacing) {
                        for y in stride(from: CGFloat.zero, through: size.height, by: PlanUITokens.patternDotSpacing) {
                            context.fill(
                                Path(
                                    ellipseIn: CGRect(
                                        x: x, y: y, width: PlanUITokens.patternDotDiameter,
                                        height: PlanUITokens.patternDotDiameter)),
                                with: .color(foreground.color.opacity(PlanUITokens.patternDotOpacity)))
                        }
                    }
                } else if [.rest, .avoidLight, .caffeineRoutine, .layover].contains(type) {
                    var path = Path()
                    for x in stride(from: -size.height, through: size.width, by: PlanUITokens.patternHatchSpacing) {
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    }
                    context.stroke(
                        path, with: .color(foreground.color.opacity(PlanUITokens.patternHatchOpacity)),
                        lineWidth: PlanUITokens.patternHatchWidth)
                }
            }.clipShape(RoundedRectangle(cornerRadius: PlanUITokens.radiusLg))
        }
        private var fill: ColorToken {
            switch type {
            case .sleep, .nap, .rest: .catSleep
            case .seekLight: .catLight
            case .lightOK, .lightNeutral: .catModerate
            case .avoidLight: .catDark
            case .caffeineServing, .caffeineRoutine, .caffeineOK: .catCaffeine
            case .noCaffeine, .note: .card
            default: .catTravel
            }
        }
        private var foreground: ColorToken {
            switch fill {
            case .catSleep: .catSleepFg
            case .catLight: .catLightFg
            case .catModerate: .catModerateFg
            case .catDark: .catDarkFg
            case .catCaffeine: .catCaffeineFg
            case .card: .foreground
            default: .catTravelFg
            }
        }
        private var symbol: String {
            switch type {
            case .sleep: "moon"
            case .nap: "bed.double"
            case .rest: "armchair"
            case .seekLight: "sun.max"
            case .lightOK: "cloud.sun"
            case .lightNeutral: "lamp.desk"
            case .avoidLight: "sunglasses"
            case .caffeineServing, .caffeineRoutine, .caffeineOK: "cup.and.saucer"
            case .noCaffeine: "cup.and.saucer.fill"
            case .flight: "airplane"
            case .layover: "clock"
            case .transfer: "arrow.left.arrow.right"
            case .movementBreak: "figure.walk"
            case .zoneChange: "globe"
            default: "info.circle"
            }
        }
    }

    struct PlanBadge: View {
        enum Variant { case dawn, secondary, outline }
        let text: String
        var variant: Variant
        init(text: String, active: Bool = false) {
            self.text = text
            variant = active ? .dawn : .secondary
        }
        init(text: String, variant: Variant) {
            self.text = text
            self.variant = variant
        }
        var body: some View {
            Text(text).planTextStyle(Typography.screenMeta, color: foreground).padding(.horizontal, PlanUITokens.space2)
                .padding(.vertical, AuthTokens.borderWidth)
                .foregroundStyle(foreground.color)
                .background {
                    if variant != .outline {
                        Capsule().fill((variant == .dawn ? ColorToken.dawn : .secondary).color)
                    }
                }
                .overlay {
                    if variant == .outline {
                        Capsule().strokeBorder(ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                    }
                }
        }
        private var foreground: ColorToken {
            switch variant {
            case .dawn: .dawnForeground
            case .secondary: .secondaryForeground
            case .outline: .foreground
            }
        }
    }

    struct PriorityTag: View {
        let text: String
        var body: some View {
            Text(text).planTextStyle(Typography.screenPriorityTag)
                .padding(.horizontal, PlanUITokens.space1 + PlanUITokens.space1 / 2)
                .padding(.vertical, AuthTokens.borderWidth)
                .background(ColorToken.background.color.opacity(PlanUITokens.priorityTagOpacity), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        ColorToken.foreground.color.opacity(PlanUITokens.priorityTagOpacity),
                        lineWidth: AuthTokens.borderWidth)
                }
        }
    }

    struct PrioritySample: View {
        let priority: Priority
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: PlanUITokens.radiusLg)
            shape.fill((priority == .info ? ColorToken.muted : .catSleep).color)
                .overlay {
                    shape.strokeBorder(
                        priority == .optional
                            ? ColorToken.foreground.color.opacity(PlanUITokens.priorityOptionalOpacity)
                            : ColorToken.border.color,
                        style: StrokeStyle(
                            lineWidth: AuthTokens.borderWidth,
                            dash: priority == .optional ? [PlanUITokens.space1] : []))
                }
                .overlay(alignment: .leading) {
                    if priority == .core {
                        Rectangle().fill(ColorToken.foreground.color.opacity(PlanUITokens.priorityCoreOpacity))
                            .frame(width: PlanUITokens.space1)
                    }
                }
                .clipShape(shape).saturation(priority == .info ? PlanUITokens.priorityInfoSaturation : 1)
                .frame(width: PlanUITokens.prioritySampleWidth, height: PlanUITokens.prioritySampleHeight)
                .accessibilityHidden(true)
        }
    }

    extension View {
        func planEmptyCard() -> some View {
            padding(PlanUITokens.space5)
                .overlay {
                    RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                        .strokeBorder(
                            ColorToken.border.color,
                            style: StrokeStyle(lineWidth: AuthTokens.focusWidth, dash: [PlanUITokens.space1]))
                }
        }
        func planCard(active: Bool = false, completed: Bool = false) -> some View {
            padding(PlanUITokens.space5)
                .background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl))
                .overlay {
                    RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                        .strokeBorder(
                            (active ? ColorToken.dawn : .border).color,
                            lineWidth: active ? AuthTokens.focusWidth : AuthTokens.borderWidth)
                }
                .opacity(completed ? PlanUITokens.completedCardOpacity : 1)
        }
    }
#endif
