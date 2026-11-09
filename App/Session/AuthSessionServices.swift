import AppCore
import Auth
import Foundation
import UIKit

@MainActor
final class AuthSessionServices {
    let nativeSession: NativeSessionController
    let model: SignInModel

    init(
        services: AppServices, applicationSupport support: URL, nativeSession native: NativeSessionController,
        navigator: RootNavigator, source: (any DataSource)? = nil,
        anchor: @escaping @MainActor () -> UIWindow? = { nil },
        assertionProvider: (any PasskeyAssertionProviding)? = nil,
        verification: @escaping @MainActor (UInt64) async -> Void
    ) {
        let namespace = services.namespace
        let credentials = KeychainSessionStore(namespace: namespace)
        nativeSession = native
        let source = source ?? services.makeDataSource(applicationSupport: support, credentials: credentials)
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
        native.observe()
    }
}
