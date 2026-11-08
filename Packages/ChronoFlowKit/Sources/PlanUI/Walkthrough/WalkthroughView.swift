#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    public struct WalkthroughView: View {
        @Environment(\.locale) private var locale
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.forcesReduceMotion) private var forcesReduceMotion
        @AccessibilityFocusState private var titleFocused: Bool
        public let model: WalkthroughModel

        public init(model: WalkthroughModel) { self.model = model }

        private var copy: WalkthroughCopy {
            WalkthroughCopy(language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }

        public var body: some View {
            GeometryReader { safeGeometry in
                GeometryReader { window in
                    let insets = safeGeometry.safeAreaInsets
                    let layout = WalkthroughGeometry(
                        size: window.size,
                        insets: .init(
                            top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing))
                    VStack(spacing: 0) {
                        header
                        GeometryReader { viewport in
                            ScrollView {
                                VStack(alignment: .leading, spacing: PlanUITokens.walkthroughContentGap) {
                                    WalkthroughPreview(page: model.page, copy: copy)
                                    VStack(alignment: .leading, spacing: PlanUITokens.walkthroughCopyGap) {
                                        WelcomeText(
                                            copy(model.page.title), style: Typography.screenPageTitle,
                                            color: .foreground
                                        )
                                        .accessibilityAddTraits(.isHeader)
                                        .accessibilityIdentifier("walkthrough.title")
                                        .accessibilityFocused($titleFocused)
                                        WelcomeText(
                                            copy(model.page.detail), style: Typography.screenBodyLg,
                                            color: .mutedForeground)
                                    }.padding(.horizontal, PlanUITokens.space1)
                                }.frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .center)
                            }.scrollIndicators(.hidden).id(model.page)
                        }
                        footer
                    }
                    .frame(width: layout.content.width, height: layout.content.height)
                    .padding(.top, layout.top).padding(.bottom, layout.bottom)
                    .padding(.leading, layout.leading).padding(.trailing, layout.trailing)
                    .background(ColorToken.background.color)
                }.ignoresSafeArea()
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("walkthrough.screen")
            .onChange(of: model.page) { _, _ in titleFocused = true }
        }

        private var header: some View {
            HStack {
                WelcomeText(
                    copy("{{current}} of {{total}}", ["current": String(model.page.rawValue + 1), "total": "3"])
                        .uppercased(with: locale),
                    style: Typography.screenEyebrow, color: .dawnText
                ).monospacedDigit().padding(.leading, PlanUITokens.space1)
                    .accessibilityIdentifier("walkthrough.counter")
                Spacer(minLength: PlanUITokens.space2)
                Button {
                    Task { await model.skip() }
                } label: {
                    WelcomeText(copy("Skip"), style: Typography.authLabel, color: .foreground)
                        .padding(.horizontal, PlanUITokens.space3).frame(minHeight: AuthTokens.touch)
                        .contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("walkthrough.skip")
            }.frame(minHeight: PlanUITokens.actionMinHeight).disabled(model.busy || model.completed)
        }

        private var footer: some View {
            VStack(spacing: PlanUITokens.space5) {
                HStack(spacing: PlanUITokens.space2) {
                    ForEach(WalkthroughModel.Page.allCases, id: \.self) { page in
                        Capsule().fill((page == model.page ? ColorToken.dawn : .border).color)
                            .frame(
                                width: page == model.page ? PlanUITokens.space6 : PlanUITokens.space2,
                                height: PlanUITokens.space2)
                    }
                }.accessibilityHidden(true)
                    .animation(
                        reduceMotion || forcesReduceMotion
                            ? nil : .easeInOut(duration: PlanUITokens.walkthroughDotDuration),
                        value: model.page)
                Button {
                    Task { await model.advance() }
                } label: {
                    WelcomeText(
                        copy(model.page == .progress ? "Done" : "Next"), style: Typography.authLabel,
                        color: .primaryForeground
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: model.page == .progress
                            ? PlanUITokens.walkthroughDoneHeight : PlanUITokens.walkthroughNextHeight
                    )
                    .background(ColorToken.primary.color, in: Capsule())
                    .frame(minHeight: AuthTokens.touch).contentShape(Capsule())
                }.buttonStyle(.plain).disabled(model.busy || model.completed)
                    .accessibilityIdentifier(model.page == .progress ? "walkthrough.done" : "walkthrough.next")
            }
        }
    }
#endif
