#if canImport(UIKit)
    import AppCore
    import DesignSystem
    import LocalStore
    import SwiftUI
    import UIKit

    public enum SettingsDestination: String, CaseIterable, Identifiable {
        case profile, account, security, bodyClock, preferences, plan
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .profile: "Profile"
            case .account: "Account"
            case .security: "Security"
            case .bodyClock: "Body clock"
            case .preferences: "Preferences"
            case .plan: "Plan & credits"
            }
        }
        var subtitle: String? {
            switch self {
            case .account: "Profile, language, your data"
            case .security: "Password, passkeys, two-factor"
            case .bodyClock: "The answers every plan is built from"
            case .preferences: "Appearance, timeline, reminders"
            default: nil
            }
        }
        var symbol: String {
            switch self {
            case .profile, .account: "person"
            case .security: "shield"
            case .bodyClock: "moon"
            case .preferences: "slider.horizontal.3"
            case .plan: "creditcard"
            }
        }
    }

    @MainActor public struct SettingsHomeView: View {
        @Environment(\.locale) private var locale
        @Bindable private var model: SettingsHomeModel
        public init(model: SettingsHomeModel) { self.model = model }
        private var language: Language { locale.language.languageCode?.identifier == "nl" ? .nl : .en }
        private func t(_ key: String) -> String { SettingsStrings.text(key, language: language) }

        public var body: some View {
            List {
                if let account = model.state.account {
                    Section {
                        #if DEBUG
                            NavigationLink(value: SettingsDestination.profile) { profile(account) }
                                .accessibilityIdentifier("settings.profile")
                        #else
                            profile(account).accessibilityIdentifier("settings.profile")
                        #endif
                    }.listRowBackground(ColorToken.card.color)
                        .listRowInsets(
                            EdgeInsets(top: 0, leading: PlanUITokens.space4, bottom: 0, trailing: PlanUITokens.space4))
                }
                if let copy = model.state.syncCopy(now: model.now, syncing: model.syncing, offline: model.offline) {
                    Section {
                        Label(
                            syncText(copy),
                            systemImage: model.state.pendingCount > 0
                                ? "icloud.and.arrow.up" : model.offline ? "icloud.slash" : "checkmark.icloud"
                        )
                        .font(Typography.screenMeta.font).foregroundStyle(ColorToken.mutedForeground.color)
                        .monospacedDigit().accessibilityElement(children: .combine)
                        .accessibilityIdentifier("settings.sync")
                    }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                #if DEBUG
                    Section {
                        ForEach(SettingsDestination.allCases.filter { $0 != .profile }) { destination in
                            NavigationLink(value: destination) { row(destination) }
                                .accessibilityIdentifier("settings.\(destination.rawValue)")
                        }
                    }.listRowBackground(ColorToken.card.color)
                        .listRowInsets(
                            EdgeInsets(top: 0, leading: PlanUITokens.space4, bottom: 0, trailing: PlanUITokens.space4))
                #endif
                Section {
                    Button {
                        Task { await model.signOut() }
                    } label: {
                        Text(t("Sign out")).font(Typography.screenLabel.font).frame(maxWidth: .infinity)
                            .frame(minHeight: PlanUITokens.actionMinHeight)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .disabled(model.busy || model.state.account == nil).accessibilityIdentifier("settings.signOut")
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(ColorToken.background.color).foregroundStyle(ColorToken.cardForeground.color)
            .tint(ColorToken.primary.color)
            .navigationTitle(t("Settings")).navigationBarTitleDisplayMode(.large)
            .background(SettingsNavigationStyle())
            .accessibilityIdentifier("settings.screen")
            .sheet(isPresented: $model.showsPending) { SignOutPendingSheet(model: model) }
        }

        private func profile(_ account: AccountRecord) -> some View {
            HStack(spacing: PlanUITokens.space3) {
                Text(model.state.initials).font(Typography.screenBodyLg.font).fontWeight(.semibold)
                    .frame(width: AuthTokens.touch, height: AuthTokens.touch)
                    .foregroundStyle(ColorToken.primaryForeground.color)
                    .background(ColorToken.primary.color, in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.name).font(Typography.screenBodyLg.font).fontWeight(.semibold)
                    Text(account.email).font(Typography.screenBody.font).foregroundStyle(
                        ColorToken.mutedForeground.color
                    )
                    .lineLimit(1)
                }
            }.padding(.vertical, PlanUITokens.space3).frame(minHeight: PlanUITokens.space16 + PlanUITokens.space2)
                .accessibilityElement(children: .combine)
        }

        private func row(_ destination: SettingsDestination) -> some View {
            HStack(spacing: PlanUITokens.space3) {
                Image(systemName: destination.symbol).font(Typography.screenBodyLg.font)
                    .frame(
                        width: PlanUITokens.space8 + PlanUITokens.space1,
                        height: PlanUITokens.space8 + PlanUITokens.space1
                    )
                    .background(ColorToken.muted.color, in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: PlanUITokens.space1) {
                    Text(t(destination.title)).font(Typography.screenBodyLg.font).fontWeight(.medium)
                    if let subtitle = destination.subtitle {
                        Text(t(subtitle)).font(Typography.screenBody.font).foregroundStyle(
                            ColorToken.mutedForeground.color)
                    } else if destination == .plan, let credits = model.state.credits {
                        Text(SettingsStrings.text("%lld credits left", language: language, count: credits))
                            .font(Typography.screenBody.font).foregroundStyle(ColorToken.mutedForeground.color)
                            .monospacedDigit()
                    }
                    if destination == .bodyClock, model.state.missingAnswers > 0 {
                        Text(
                            SettingsStrings.text(
                                "%lld to answer", language: language, count: model.state.missingAnswers)
                        )
                        .font(Typography.screenMeta.font).foregroundStyle(ColorToken.dawnForeground.color)
                        .padding(.horizontal, PlanUITokens.space2).padding(.vertical, PlanUITokens.space1)
                        .background(ColorToken.dawn.color, in: Capsule())
                        .accessibilityIdentifier("settings.readiness")
                    }
                }
            }.frame(minHeight: PlanUITokens.space16).accessibilityElement(children: .combine)
        }

        private func syncText(_ copy: SettingsCopy) -> String {
            guard copy.key == "Synced on {{date}}", let raw = copy.values["date"],
                let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
                    ?? (try? Date.ISO8601FormatStyle().parse(raw))
            else { return copy.text(language: language) }
            return SettingsStrings.text(
                copy.key, language: language,
                ["date": date.formatted(.dateTime.day().month(.abbreviated).locale(locale))])
        }
    }

    private struct SettingsNavigationStyle: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> Styler { Styler() }
        func updateUIViewController(_ controller: Styler, context: Context) { controller.style() }
        final class Styler: UIViewController {
            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                style()
            }
            override func viewDidLayoutSubviews() {
                super.viewDidLayoutSubviews()
                style()
            }
            func style() {
                guard let bar = navigationController?.navigationBar else { return }
                let font = Typography.screenPageTitleLg.uiFont(compatibleWith: traitCollection)
                guard bar.standardAppearance.largeTitleTextAttributes[.font] as? UIFont != font else { return }
                let appearance = UINavigationBarAppearance(barAppearance: bar.standardAppearance)
                appearance.largeTitleTextAttributes = [
                    .font: font, .foregroundColor: UIColor(ColorToken.foreground.color),
                ]
                bar.standardAppearance = appearance
                bar.scrollEdgeAppearance = appearance
            }
        }
    }
#endif
