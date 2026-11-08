#if canImport(UIKit)
    import DesignSystem
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

    extension SettingsDestination {
        public var canNavigate: Bool {
            #if DEBUG
                true
            #else
                isBuilt
            #endif
        }
        public var isBuilt: Bool {
            self == .account || self == .profile || self == .bodyClock || self == .preferences || self == .security
        }
        public static var visible: [Self] {
            #if DEBUG
                allCases
            #else
                allCases.filter(\.isBuilt)
            #endif
        }
    }

    @MainActor public struct SettingsHomeView: View {
        @Environment(\.locale) private var locale
        @Bindable private var model: SettingsHomeModel
        public init(model: SettingsHomeModel) { self.model = model }

        public var body: some View {
            SettingsHomeContent(model: model, navigationEnabled: true)
                .navigationTitle(
                    SettingsStrings.text(
                        "Settings", language: locale.language.languageCode?.identifier == "nl" ? .nl : .en)
                )
                .navigationBarTitleDisplayMode(.large)
                .background(SettingsNavigationStyle())
                .sheet(isPresented: $model.showsPending) { SignOutPendingSheet(model: model) }
        }
    }

    @MainActor public struct SettingsHomeContent: View {
        private let model: SettingsHomeModel
        private let navigationEnabled: Bool

        public init(model: SettingsHomeModel, navigationEnabled: Bool = false) {
            self.model = model
            self.navigationEnabled = navigationEnabled
        }

        public var body: some View {
            List {
                if let account = model.state.account {
                    Section {
                        destination(.profile) { SettingsProfileRow(account: account, initials: model.state.initials) }
                            .accessibilityIdentifier("settings.profile")
                    }.listRowBackground(ColorToken.card.color)
                        .listRowInsets(
                            EdgeInsets(top: 0, leading: PlanUITokens.space4, bottom: 0, trailing: PlanUITokens.space4))
                }
                if let copy = model.state.syncCopy(now: model.now, syncing: model.syncing, offline: model.offline) {
                    Section {
                        SettingsSyncRow(copy: copy, pending: model.state.pendingCount > 0, offline: model.offline)
                    }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Section {
                    ForEach(SettingsDestination.visible.filter { $0 != .profile }) { destination in
                        self.destination(destination) {
                            SettingsDestinationRow(
                                destination: destination, credits: model.state.credits,
                                missingAnswers: model.state.missingAnswers)
                        }
                        .accessibilityIdentifier("settings.\(destination.rawValue)")
                    }
                }.listRowBackground(ColorToken.card.color)
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: PlanUITokens.space4, bottom: 0, trailing: PlanUITokens.space4))
                Section {
                    SettingsSignOutButton(model: model)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(ColorToken.background.color).foregroundStyle(ColorToken.cardForeground.color)
            .tint(ColorToken.primary.color)
            .accessibilityElement(children: .contain).accessibilityIdentifier("settings.screen")
        }

        @ViewBuilder private func destination<Label: View>(
            _ destination: SettingsDestination, @ViewBuilder label: () -> Label
        ) -> some View {
            if navigationEnabled, destination.canNavigate {
                NavigationLink(value: destination, label: label)
            } else {
                label()
            }

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
