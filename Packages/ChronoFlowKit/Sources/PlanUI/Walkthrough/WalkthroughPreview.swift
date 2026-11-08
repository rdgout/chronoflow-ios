#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import PlanCore
    import SwiftUI

    struct WalkthroughPreview: View {
        @Environment(\.colorScheme) private var scheme
        let page: WalkthroughModel.Page
        let copy: WalkthroughCopy

        var body: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.walkthroughCopyGap) {
                switch page {
                case .timeline: timeline
                case .categories: categories
                case .progress: progress
                }
            }.padding(PlanUITokens.space5).frame(maxWidth: .infinity, alignment: .leading)
                .background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl))
                .overlay {
                    RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                        .strokeBorder(ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                }
                .background {
                    let spread = scheme == .dark ? AuthTokens.darkShadowSpread : AuthTokens.lightShadowSpread
                    RoundedRectangle(cornerRadius: max(0, PlanUITokens.radius3Xl + spread))
                        .fill(ColorToken.card.color)
                        .shadow(
                            color: ColorToken.authShadow.color,
                            radius: scheme == .dark ? AuthTokens.darkShadowRadius : AuthTokens.lightShadowRadius,
                            y: scheme == .dark ? AuthTokens.darkShadowY : AuthTokens.lightShadowY
                        )
                        .padding(-spread)
                }
                .accessibilityHidden(true).allowsHitTesting(false)
        }

        private var timeline: some View {
            VStack(spacing: PlanUITokens.walkthroughCopyGap) {
                block(.sleep, title: "Sleep", time: "23:00–07:00")
                block(.seekLight, title: "Seek bright light", time: "08:00–10:00")
                block(.caffeineServing, title: "1 cup of coffee", time: "09:30")
                block(.flight, title: "KL 861", time: "14:40–09:15")
            }
        }

        private func block(_ type: BlockType, title: String, time: String) -> some View {
            let style = PlanCategoryStyle(type)
            let caffeine = type == .caffeineServing
            return ViewThatFits(in: .horizontal) {
                blockContent(style: style, title: title, time: time, compact: false, caffeine: caffeine)
                    .frame(minWidth: PlanUITokens.walkthroughCompactWidth)
                blockContent(style: style, title: title, time: time, compact: true, caffeine: caffeine)
            }
            .padding(PlanUITokens.space1 + PlanUITokens.space1 / 2)
            .frame(maxWidth: .infinity, minHeight: PlanUITokens.walkthroughBlockHeight)
            .background(style.fill.color)
            .overlay(alignment: .leading) {
                if !caffeine {
                    Rectangle().fill(ColorToken.foreground.color.opacity(PlanUITokens.priorityCoreOpacity))
                        .frame(width: PlanUITokens.space1)
                } else {
                    PlanPattern(dots: true).fill(style.foreground.color.opacity(PlanUITokens.patternDotOpacity))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: caffeine ? PlanUITokens.radiusFull : PlanUITokens.radiusLg))
        }

        private func blockContent(style: PlanCategoryStyle, title: String, time: String, compact: Bool, caffeine: Bool)
            -> some View
        {
            VStack(alignment: .leading, spacing: PlanUITokens.space1 / 2) {
                HStack(spacing: PlanUITokens.space1) {
                    Image(systemName: style.icon).font(.system(size: PlanUITokens.space3 + PlanUITokens.space1 / 2))
                    if !compact {
                        Text(
                            caffeine
                                ? copy("{{title}} · {{time}}", ["title": copy(title), "time": copy(time)]) : copy(title)
                        )
                        .font(Typography.screenBlockLabel.font)
                    }
                }.frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                if !compact && !caffeine { Text(copy(time)).font(Typography.screenBlockLabel.font) }
            }.foregroundStyle(style.foreground.color).monospacedDigit()
        }

        private var categories: some View {
            ForEach([BlockType.sleep, .seekLight, .avoidLight, .caffeineServing, .flight], id: \.self) { type in
                HStack(spacing: PlanUITokens.space3) {
                    CategorySwatch(type)
                    WelcomeText(copy(label(type)), style: Typography.walkthroughBody, color: .foreground)
                }.frame(minHeight: AuthTokens.touch)
            }
        }

        private func label(_ type: BlockType) -> String {
            switch type {
            case .sleep: "Sleep"
            case .seekLight: "Seek bright light"
            case .avoidLight: "Avoid light"
            case .caffeineServing: "Caffeine"
            default: "Flight"
            }
        }

        private var progress: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.walkthroughCopyGap) {
                DayProgressRow(done: 3, total: 7, skipped: 0, language: copy.language)
                    .padding(.top, PlanUITokens.space1)
                row(.seekLight, title: "Seek bright light outdoors", time: "11:00", relative: "In 15 min")
                row(.caffeineServing, title: "1 cup of filter coffee", time: "10:45", relative: "Done")
            }
        }

        private func row(_ type: BlockType, title: String, time: String, relative: String) -> some View {
            HStack(spacing: PlanUITokens.space3) {
                CategorySwatch(type)
                VStack(alignment: .leading, spacing: 0) {
                    WelcomeText(copy(title), style: Typography.walkthroughBody, color: .foreground)
                    WelcomeText(
                        copy(
                            "{{time}} · {{zone}} · {{relative}}",
                            ["time": copy(time), "zone": copy("Tokyo"), "relative": copy(relative)]),
                        style: Typography.screenBody, color: .mutedForeground
                    ).monospacedDigit()
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: PlanUITokens.space14).padding(PlanUITokens.space2)
        }
    }
#endif
