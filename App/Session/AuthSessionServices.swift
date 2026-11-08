import AppCore
import Auth
import DataAccess
import Foundation
import UIKit

@MainActor
final class AuthSessionServices {
    let nativeSession: NativeSessionController
    let model: SignInModel
    #if DEBUG
        let authUITestEnabled: Bool
    #endif

    init(
        services: AppServices, applicationSupport support: URL, nativeSession native: NativeSessionController,
        navigator: RootNavigator, source: (any DataSource)? = nil,
        anchor: @escaping @MainActor () -> UIWindow? = { nil },
        assertionProvider: (any PasskeyAssertionProviding)? = nil,
        verification: @escaping @MainActor (UInt64) async -> Void
    ) {
        #if DEBUG
            authUITestEnabled = services.authUITestEnabled
        #endif
        let credentials = services.sessionCredentials()
        nativeSession = native
        let source = source ?? services.makeDataSource(applicationSupport: support, credentials: credentials)
        #if DEBUG
            if services.factory.source == .mock, let mock = source as? MockDataSource,
                ProcessInfo.processInfo.arguments.contains("-cf.twoFactorServerFailure")
            {
                Task { await mock.failNext(method: .completeTwoFactor, error: .server(status: 503)) }
            }
            if services.factory.source == .mock, let mock = source as? MockDataSource {
                if services.authUITestEnabled,
                    let failure = ProcessInfo.processInfo.environment["CF_AUTH_TEST_RESET_FAILURE"]
                {
                    Task {
                        await mock.failNext(
                            method: .resetPassword,
                            error: failure == "offline"
                                ? .offline
                                : failure == "throttle"
                                    ? .throttled(retryAfterSeconds: 60, status: 429) : .server(status: 503))
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("-cf.forgotServerFailure") {
                    Task { await mock.failNext(method: .requestPasswordReset, error: .server(status: 503)) }
                } else if ProcessInfo.processInfo.arguments.contains("-cf.forgotThrottleFailure") {
                    Task {
                        await mock.failNext(
                            method: .requestPasswordReset, error: .throttled(retryAfterSeconds: 60, status: 429))
                    }
                }
            }
        #endif
        let identity = DeviceIdentityStore(persistence: DevicePreferences())
        let assertion: any PasskeyAssertionProviding =
            assertionProvider
            ?? (services.factory.source == .mock
                ? DeterministicAssertionProvider { _ in throw PasskeyFailure.unavailable }
                : SystemPasskeyAssertionProvider(anchor: anchor))
        model = SignInModel(
            source: source, session: native.controller,
            deviceIdentity: { try await identity.identity() },
            deviceName: DeviceIdentityStore.deviceName(UIDevice.current.name, model: UIDevice.current.model),
            assertionProvider: assertion,
            route: { _ in await native.routeAcceptedSession(navigator: navigator, verification: verification) })
        if let mock = source as? MockDataSource {
            model.mockMail = {
                guard let event = try? await mock.inbox().last else { return nil }
                if case .passwordReset(_, _, _, let input) = event {
                    return .reset(ResetPasswordLink(token: input.token, email: input.email))
                }
                return nil
            }
        }
        native.observe()
    }
}
