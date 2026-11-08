#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import SwiftUI

    public struct TermsUpdateView: View {
        @Environment(\.locale) private var locale
        @Bindable private var signOut: SettingsHomeModel
        private let model: TermsUpdateModel

        public init(model: TermsUpdateModel, signOut: SettingsHomeModel) {
            self.model = model
            self.signOut = signOut
        }

        private func t(_ key: String) -> String {
            TermsStrings.text(key, language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
        }

        public var body: some View {
            GeometryReader { safe in
                GeometryReader { window in
                    let insets = safe.safeAreaInsets
                    let layout = TermsGeometry(
                        size: window.size,
                        insets: .init(
                            top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing))
                    ScrollView {
                        VStack(alignment: .leading, spacing: PlanUITokens.space5) {
                            header
                            heading
                            summary
                            Spacer(minLength: 0)
                            if model.failed {
                                AuthBanner(
                                    title: t("Couldn't save your answer."),
                                    message: t(
                                        "Check your connection and try again. You can keep reading the policy meanwhile."
                                    )
                                ).accessibilityIdentifier("terms.failure")
                            }
                            actions
                        }.frame(maxWidth: .infinity, minHeight: layout.content.height)
                            .padding(.top, layout.top).padding(.bottom, layout.bottom)
                            .padding(.leading, layout.leading).padding(.trailing, layout.trailing)
                    }.scrollIndicators(.hidden)
                }.ignoresSafeArea()
            }
            .foregroundStyle(ColorToken.foreground.color).background(ColorToken.background.color)
            .tint(ColorToken.primary.color)
            .accessibilityElement(children: .contain).accessibilityIdentifier("terms.screen")
            .sheet(isPresented: $signOut.showsPending) { SignOutPendingSheet(model: signOut) }
        }

        private var header: some View {
            HStack(spacing: AuthTokens.bannerGap) {
                Image("TermsBrand", bundle: .module).resizable()
                    .frame(width: TermsTokens.brandSize, height: TermsTokens.brandSize).accessibilityHidden(true)
                WelcomeText(
                    t("Before you continue").uppercased(with: locale), style: Typography.screenEyebrow, color: .dawnText
                )
            }.frame(minHeight: AuthTokens.touch)
        }

        private var heading: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space2) {
                WelcomeText(t("We've updated our terms"), style: Typography.termsTitle, color: .foreground)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("terms.title")
                WelcomeText(
                    t(
                        "The new terms and privacy policy apply from [effective date]. Please accept them to keep using ChronoFlow."
                    ),
                    style: Typography.screenBodyLg, color: .mutedForeground)
            }
        }

        private var summary: some View {
            VStack(alignment: .leading, spacing: PlanUITokens.space3) {
                WelcomeText(
                    t("What changed").uppercased(with: locale), style: Typography.screenLabel, color: .mutedForeground
                )
                .accessibilityAddTraits(.isHeader)
                ForEach(["[Change one]", "[Change two]", "[Change three]"], id: \.self) { title in
                    HStack(alignment: .top, spacing: PlanUITokens.space3) {
                        Circle().fill(ColorToken.dawn.color)
                            .frame(width: TermsTokens.bulletSize, height: TermsTokens.bulletSize)
                            .padding(.top, PlanUITokens.space2).accessibilityHidden(true)
                        (Text(verbatim: t(title)).font(Typography.termsStrong.font).foregroundColor(
                            ColorToken.foreground.color)
                            + Text(verbatim: " " + t("[One sentence on what changes for the user.]"))
                            .font(Typography.termsBody.font).foregroundColor(ColorToken.mutedForeground.color)).frame(
                                maxWidth: .infinity, alignment: .leading)
                    }
                }
                Link(destination: URL(string: "https://chronoflow.net/terms")!) {
                    HStack(spacing: PlanUITokens.space3) {
                        Image(systemName: "doc.text").accessibilityHidden(true)
                        WelcomeText(
                            t("Read the full terms and privacy policy"), style: Typography.termsBody, color: .foreground
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").foregroundStyle(ColorToken.mutedForeground.color)
                            .accessibilityHidden(true)
                    }.padding(.horizontal, AuthTokens.bannerHorizontal).padding(.vertical, PlanUITokens.space2)
                        .frame(minHeight: TermsTokens.policyHeight)
                        .background(ColorToken.card.color, in: RoundedRectangle(cornerRadius: PlanUITokens.space4))
                }.buttonStyle(.plain).foregroundStyle(ColorToken.foreground.color)
                    .padding(.top, PlanUITokens.space1).accessibilityIdentifier("terms.policy")
            }.padding(TermsTokens.summaryPadding)
                .background(ColorToken.surface2.color, in: RoundedRectangle(cornerRadius: PlanUITokens.radius2Xl))
        }

        private var actions: some View {
            VStack(spacing: PlanUITokens.space2) {
                if signOut.failure != nil {
                    WelcomeText(t("Something went wrong"), style: Typography.screenBody, color: .destructive)
                        .accessibilityIdentifier("terms.signOutFailure")
                }
                Button {
                    Task { await model.accept() }
                } label: {
                    Text(verbatim: t(model.failed ? "Try again" : "Accept and continue"))
                        .frame(maxWidth: .infinity, minHeight: PlanUITokens.actionMinHeight)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .disabled(!model.canAccept || signOut.busy).accessibilityIdentifier("terms.accept")
                Button {
                    Task { await signOut.signOut() }
                } label: {
                    Text(verbatim: t("Sign out")).frame(maxWidth: .infinity, minHeight: PlanUITokens.actionMinHeight)
                }.buttonStyle(.borderless).foregroundStyle(ColorToken.foreground.color)
                    .disabled(model.busy || model.completed || signOut.busy).accessibilityIdentifier("terms.signOut")
                WelcomeText(
                    t("Your trips stay saved if you sign out."), style: Typography.screenMeta, color: .mutedForeground
                )
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, PlanUITokens.space1)
            }.font(Typography.authLabel.font)
        }
    }
#endif
