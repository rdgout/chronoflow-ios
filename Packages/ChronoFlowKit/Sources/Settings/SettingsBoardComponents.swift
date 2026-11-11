#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit

    struct SettingsCard<Content: View>: View {
        var rows = false
        var shadow = true
        var spacing: CGFloat = PlanUITokens.space4
        @ViewBuilder let content: Content
        var body: some View {
            VStack(alignment: .leading, spacing: rows ? 0 : spacing) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(rows ? 0 : PlanUITokens.space5)
                .background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: radius))
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(ColorToken.border.color, lineWidth: AuthTokens.borderWidth)
                }
                .settingsSoftShadow(enabled: !rows && shadow)
        }
        private var radius: CGFloat { rows ? PlanUITokens.radius2Xl : PlanUITokens.radius3Xl }
    }

    struct SettingsReadOnlyField: View {
        let title: String
        let value: String
        var body: some View {
            VStack(alignment: .leading, spacing: AuthTokens.fieldGap) {
                WelcomeText(title, style: Typography.authLabel, color: .cardForeground)
                Text(value).settingsFont(Typography.authBody).textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: AuthTokens.touch, alignment: .leading)
                    .padding(.horizontal, AuthTokens.inset)
                    .overlay {
                        RoundedRectangle(cornerRadius: AuthTokens.fieldRadius)
                            .strokeBorder(ColorToken.input.color, lineWidth: AuthTokens.borderWidth)
                    }
            }.accessibilityElement(children: .combine)
        }
    }

    struct SettingsDivider: View {
        var body: some View { ColorToken.border.color.frame(height: AuthTokens.borderWidth).accessibilityHidden(true) }
    }

    struct SettingsRow: View {
        let title: String
        var subtitle: String? = nil
        var symbol: String? = nil
        var badge: String? = nil
        var badgeOn = false
        var destructive = false
        var chevron = true
        var lock = false
        var body: some View {
            HStack(spacing: PlanUITokens.space3) {
                if let symbol {
                    Image(systemName: symbol).settingsFont(Typography.screenBodyLg)
                        .frame(width: SettingsTokens.rowDisc, height: SettingsTokens.rowDisc)
                        .background(ColorToken.muted.color, in: Circle()).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).settingsFont(Typography.settingsRow)
                        .foregroundStyle((destructive ? ColorToken.destructive : .cardForeground).color)
                    if let subtitle {
                        Text(subtitle).settingsFont(Typography.screenBody).foregroundStyle(
                            ColorToken.mutedForeground.color)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let badge { SettingsBadge(title: badge, dawn: badgeOn) }
                if lock {
                    Image(systemName: "lock").settingsFont(Typography.screenBodyLg)
                        .foregroundStyle(ColorToken.mutedForeground.color).accessibilityHidden(true)
                }
                if chevron {
                    Image(systemName: "chevron.right").settingsFont(Typography.screenBodyLg)
                        .foregroundStyle(ColorToken.mutedForeground.color).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, PlanUITokens.space4).padding(.vertical, SettingsTokens.rowVertical)
            .frame(minHeight: SettingsTokens.rowHeight).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }

    struct SettingsBadge: View {
        let title: String
        var dawn = false
        var body: some View {
            Text(title).settingsFont(Typography.settingsBadge)
                .padding(.horizontal, PlanUITokens.space2).padding(.vertical, AuthTokens.borderWidth * 2)
                .background((dawn ? ColorToken.dawn : .secondary).color, in: Capsule())
                .foregroundStyle((dawn ? ColorToken.dawnForeground : .secondaryForeground).color)
        }
    }

    struct SettingsEyebrow: View {
        let title: String
        var dawn = false
        var body: some View {
            Text(title.uppercased()).settingsFont(dawn ? Typography.screenEyebrow : Typography.settingsEyebrow)
                .foregroundStyle((dawn ? ColorToken.dawnText : .mutedForeground).color)
                .accessibilityAddTraits(.isHeader)
        }
    }

    struct SettingsLockHint: View {
        let title: String
        var body: some View {
            HStack(alignment: .top, spacing: SettingsTokens.pillGap) {
                Image(systemName: "lock").settingsFont(Typography.screenBodyLg).accessibilityHidden(true)
                Text(title).settingsFont(Typography.settingsHint)
            }.foregroundStyle(ColorToken.mutedForeground.color)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
    }

    struct SettingsError: View {
        let title: String
        var body: some View {
            Label(title, systemImage: "exclamationmark.circle").settingsFont(Typography.screenBody)
                .foregroundStyle(ColorToken.destructive.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    typealias SettingsToast = FeedbackToast

    struct SettingsOption: Identifiable {
        let id: String
        let title: String
        var hint: String? = nil
    }

    struct SettingsRadioGroup: View {
        var title: String? = nil
        let options: [SettingsOption]
        @Binding var selection: String
        var cards = false
        let identifier: String
        var body: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                if let title { Text(title).settingsFont(Typography.settingsRow) }
                if cards {
                    VStack(spacing: PlanUITokens.space2) {
                        ForEach(options) { option in choice(option) }
                    }
                } else {
                    SettingsFlowLayout(spacing: PlanUITokens.space2) {
                        ForEach(options) { option in choice(option) }
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
        }
        private func choice(_ option: SettingsOption) -> some View {
            let selected = selection == option.id
            return Button {
                selection = option.id
            } label: {
                HStack(alignment: cards ? .top : .center, spacing: cards ? PlanUITokens.space3 : SettingsTokens.pillGap)
                {
                    if selected && !cards {
                        Image(systemName: "checkmark").foregroundStyle(ColorToken.dawnText.color)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: AuthTokens.borderWidth * 2) {
                        Text(option.title).settingsFont(
                            cards
                                ? Typography.settingsStrong
                                : selected ? Typography.screenLabel : Typography.settingsPill)
                        if let hint = option.hint {
                            Text(hint).settingsFont(Typography.screenBody).foregroundStyle(
                                ColorToken.mutedForeground.color)
                        }
                    }.frame(maxWidth: cards ? .infinity : nil, alignment: .leading)
                    if cards {
                        ZStack {
                            Circle().strokeBorder(
                                (selected ? ColorToken.dawn : .mutedForeground).color.opacity(
                                    selected ? 1 : PlanUITokens.statusBorderOpacity),
                                lineWidth: SettingsTokens.selectionWidth)
                            if selected {
                                Circle().fill(ColorToken.dawn.color)
                                Image(systemName: "checkmark").settingsFont(Typography.screenMeta)
                                    .foregroundStyle(ColorToken.dawnForeground.color)
                            }
                        }.frame(width: PlanUITokens.space5, height: PlanUITokens.space5).padding(
                            .top, PlanUITokens.space1
                        ).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, PlanUITokens.space4)
                .padding(.vertical, cards ? PlanUITokens.space4 : PlanUITokens.space2)
                .frame(minHeight: SettingsTokens.pillHeight)
                .background(
                    ColorToken.card.color,
                    in: RoundedRectangle(cornerRadius: cards ? PlanUITokens.radius2Xl : PlanUITokens.radiusFull)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cards ? PlanUITokens.radius2Xl : PlanUITokens.radiusFull)
                        .strokeBorder(
                            (selected ? ColorToken.dawn : .border).color, lineWidth: SettingsTokens.selectionWidth)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(ColorToken.foreground.color)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier(identifier + "." + option.id)
        }
    }

    struct SettingsFlowLayout: Layout {
        let spacing: CGFloat
        var centered = false
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            arrange(width: proposal.width ?? .infinity, subviews: subviews).size
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let result = arrange(width: bounds.width, subviews: subviews)
            for (index, frame) in result.frames.enumerated() {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    proposal: ProposedViewSize(frame.size))
            }
        }
        private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var usedWidth: CGFloat = 0
            var frames: [CGRect] = []
            var rowStart = 0
            func centerRow() {
                guard centered else { return }
                for index in rowStart..<frames.count {
                    frames[index].origin.y += (rowHeight - frames[index].height) / 2
                }
            }
            for subview in subviews {
                let ideal = subview.sizeThatFits(.unspecified)
                let size = subview.sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
                if x > 0 && x + size.width > width {
                    centerRow()
                    rowStart = frames.count
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
                usedWidth = max(usedWidth, x + size.width)
                x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            centerRow()
            return (CGSize(width: usedWidth, height: y + rowHeight), frames)
        }
    }

    struct SettingsCompactSheet<Content: View>: View {
        var title: String? = nil
        var cancel: (() -> Void)? = nil
        var busy = false
        @ViewBuilder let content: Content
        @State private var height = PlanUITokens.space16
        @Environment(\.locale) private var locale
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: PlanUITokens.space4) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PlanUITokens.space5).padding(.top, PlanUITokens.space4)
                        .padding(.bottom, PlanUITokens.space8).planPageRail()
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            height = $0
                        }
                }
                .background(ColorToken.card.color).foregroundStyle(ColorToken.cardForeground.color)
                .settingsFont(Typography.screenBodyLg).tint(ColorToken.dawnText.color)
                .navigationTitle(title ?? "").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let cancel {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(
                                SettingsStrings.text(
                                    "Cancel", language: locale.language.languageCode?.identifier == "nl" ? .nl : .en),
                                action: cancel
                            ).disabled(busy)
                        }
                    }
                }.toolbar(title == nil ? .hidden : .visible, for: .navigationBar)
            }
            .presentationDetents([.height(height + (title == nil ? 0 : AuthTokens.touch))])
            .presentationDragIndicator(.visible).presentationCornerRadius(SettingsTokens.sheetRadius)
            .presentationBackground(ColorToken.card.color).planPageSafeArea()
            .interactiveDismissDisabled(busy)
        }
    }

    struct SettingsLoadingRows: View {
        var body: some View {
            SettingsCard(rows: true) {
                ForEach(Array(SettingsTokens.skeletonRowWidths.enumerated()), id: \.offset) { index, width in
                    if index > 0 { SettingsDivider() }
                    HStack(spacing: PlanUITokens.space3) {
                        Circle().fill(ColorToken.muted.color).frame(
                            width: SettingsTokens.rowDisc, height: SettingsTokens.rowDisc)
                        Capsule().fill(ColorToken.muted.color).frame(maxWidth: width).frame(height: PlanUITokens.space4)
                        Spacer(minLength: 0)
                    }.frame(minHeight: SettingsTokens.counterHeight).padding(.horizontal, PlanUITokens.space4)
                }
            }.accessibilityHidden(true)
        }
    }

    struct SettingsCodeText: View {
        let value: String
        @ScaledMetric(relativeTo: .body) private var size = Typography.settingsCodes.size
        var body: some View {
            let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let line =
                (Typography.settingsCodes.lineHeight ?? Typography.settingsCodes.size) * size
                / Typography.settingsCodes.size
            let leading = max(0, line - font.lineHeight)
            Text(value).font(.system(size: size, design: .monospaced)).lineSpacing(leading).padding(
                .vertical, leading / 2)
        }
    }

    extension View {
        func settingsFont(_ style: Typography.Style) -> some View { modifier(SettingsFont(style: style)) }
        func settingsSoftShadow(enabled: Bool = true) -> some View { modifier(SettingsSoftShadow(enabled: enabled)) }
    }
    private struct SettingsFont: ViewModifier {
        @Environment(\.dynamicTypeSize) private var typeSize
        let style: Typography.Style
        func body(content: Content) -> some View {
            let font = style.uiFont(
                compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize)))
            let ratio = font.pointSize / style.size
            let leading = max(0, (style.lineHeight ?? style.size) * ratio - font.lineHeight)
            content.font(.custom(style.face.rawValue, fixedSize: font.pointSize))
                .tracking(style.tracking * ratio).lineSpacing(leading).padding(.vertical, leading / 2)
        }
    }
    private struct SettingsSoftShadow: ViewModifier {
        @Environment(\.colorScheme) private var scheme
        let enabled: Bool
        func body(content: Content) -> some View {
            content.background {
                if enabled {
                    RoundedRectangle(cornerRadius: PlanUITokens.radius3Xl)
                        .inset(by: -(scheme == .dark ? AuthTokens.darkShadowSpread : AuthTokens.lightShadowSpread))
                        .fill(ColorToken.card.color)
                        .shadow(
                            color: ColorToken.authShadow.color,
                            radius: scheme == .dark ? AuthTokens.darkShadowRadius : AuthTokens.lightShadowRadius,
                            y: scheme == .dark ? AuthTokens.darkShadowY : AuthTokens.lightShadowY)
                }
            }
        }
    }
#endif
