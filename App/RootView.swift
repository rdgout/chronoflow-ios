import AppCore
import Auth
import DesignSystem
import Observation
import Settings
import SwiftUI
import Welcome

#if DEBUG
    import DataAccess
#endif

@Observable
final class RootNavigator: Navigator {
    private(set) var revision: UInt64 = 0
    private(set) var route: Route?

    init(route: Route? = nil) {
        self.route = route
    }

    func navigate(to route: Route) {
        revision &+= 1
        self.route = route
    }
}

struct RootView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var phoneLocale
    @State private var devicePreferences = SettingsDevicePreferences(defaults: SettingsPreferenceStore.make())
    var navigator = RootNavigator()
    var authModel: SignInModel?
    var authServices: AuthSessionServices?
    var moonAnchorStore: MoonAnchorStore?
    var launchIntro: LaunchIntro?
    var forcesReduceMotion = false

    private static let refreshTint: Void = {
        UIRefreshControl.appearance().tintColor = ColorToken.primary.uiColor
    }()

    @ViewBuilder private var animationConfiguredContent: some View {
        #if DEBUG
            content.transaction {
                if AuthUITestConfiguration(environment: UITestRuntime.environment)?.fastLaunch == true {
                    $0.disablesAnimations = true
                    $0.animation = nil
                }
            }
        #else
            content
        #endif
    }

    var body: some View {
        let _ = Self.refreshTint
        animationConfiguredContent
            .environment(devicePreferences)
            .environment(\.locale, devicePreferences.resolvedLocale(phone: phoneLocale))
            .preferredColorScheme(
                devicePreferences.theme == .system ? nil : devicePreferences.theme == .dark ? .dark : .light
            )
            .dynamicTypeSize(...ContentSizeCap.maximum)
            .environment(\.dynamicTypeSize, ContentSizeCap.clamp(dynamicTypeSize))
    }

    @ViewBuilder private var content: some View {
        #if DEBUG || CHRONOFLOW_TIMELINE_PERF
            if let trip = TripPageDiagnosticRoot.requestedTrip {
                TripPageDiagnosticRoot(requestedTrip: trip)
            } else {
                routedContent
            }
        #else
            routedContent
        #endif
    }

    @ViewBuilder private var routedContent: some View {
        if let route = navigator.route {
            if route == .welcome {
                WelcomeView()
                    .environment(\.welcomeNavigator, navigator)
                    .environment(\.moonAnchorStore, moonAnchorStore)
                    .environment(\.launchIntro, launchIntro)
                    .environment(\.forcesReduceMotion, forcesReduceMotion)
            } else if route == .signIn, let authModel {
                AuthRootView(
                    model: authModel, back: { navigator.navigate(to: .welcome) },
                    guest: { navigator.navigate(to: .guestWizard) })
            } else if route == .guestWizard, let authServices {
                GuestWizardDestination(services: authServices, navigator: navigator).id(navigator.revision)
            } else if route == .today {
                AppTabs(native: authServices?.nativeSession)
            } else if route == .terms, let native = authServices?.nativeSession {
                TermsDestination(native: native).id(navigator.revision)
            } else if route == .walkthrough, let native = authServices?.nativeSession {
                WalkthroughDestination(native: native)
                    .environment(\.forcesReduceMotion, forcesReduceMotion)
                    .id(navigator.revision)
            } else if route == .verify, let model = authServices?.verifyModel {
                VerifyEmailView(model: model).id(ObjectIdentifier(model))
            } else {
                #if DEBUG
                    RoutePlaceholder(route: route)
                #else
                    EmptyView()
                #endif
            }
        }
    }
}
