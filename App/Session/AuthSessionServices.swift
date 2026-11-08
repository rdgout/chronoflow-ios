import AppCore
import Auth
import DataAccess
import Foundation
import LocalStore
import Observation
import UIKit

@MainActor @Observable
final class AuthSessionServices {
    let resetLinks: GuestResetLinkRouter
    let nativeSession: NativeSessionController
    let model: SignInModel
    private let source: any DataSource
    private let navigator: RootNavigator
    private let verification: @MainActor (UInt64) async -> Void
    private(set) var verifyModel: VerifyEmailModel?
    private var pendingVerification: AuthLink?
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
        self.source = source
        self.navigator = navigator
        self.verification = verification
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
                if services.authUITestEnabled,
                    let failure = ProcessInfo.processInfo.environment["CF_AUTH_TEST_SIGNUP_FAILURE"]
                {
                    Task {
                        await mock.failNext(
                            method: .signUp,
                            error: failure == "offline"
                                ? .offline
                                : failure == "throttle"
                                    ? .throttled(retryAfterSeconds: 60, status: 429) : .server(status: 503))
                    }
                }
                if services.authUITestEnabled,
                    let state = ProcessInfo.processInfo.environment["CF_AUTH_TEST_VERIFY_STATE"],
                    ["server", "offline", "failedServer", "failedOffline"].contains(state)
                {
                    Task {
                        await mock.failNext(
                            method: .resendVerificationEmail,
                            error: state.lowercased().hasSuffix("offline") ? .offline : .server(status: 503))
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
        resetLinks = GuestResetLinkRouter(session: native.controller) { [model, navigator] input in
            navigator.navigate(to: .signIn)
            model.openReset(input)
        }
        if let mock = source as? MockDataSource {
            model.mockMail = { email in
                let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let events = try? await mock.inbox(),
                    case .passwordReset(_, _, _, let input) = events.last(where: {
                        if case .passwordReset(_, let to, _, _) = $0 { return to.lowercased() == normalized }
                        return false
                    })
                else { return nil }
                return .reset(ResetPasswordLink(token: input.token, email: input.email))
            }
        }

        native.observe()
    }
    func verificationContext() async -> VerificationContext? {
        guard let snapshot = await nativeSession.controller.activeSession(),
            let database = await nativeSession.accounts.activeDatabase(),
            let account = try? await AccountRepository(database: database).account(),
            account.id == snapshot.session.accountId,
            await nativeSession.controller.activeSession() == snapshot
        else { return nil }
        return VerificationContext(accountID: account.id, email: account.email, epoch: snapshot.epoch)
    }

    func receiveVerificationLink(_ input: SignedVerificationInput?) async {
        pendingVerification = .verify(input)
        if await nativeSession.controller.activeSession() == nil {
            model.clearSecrets()
            navigator.navigate(to: .signIn)
            return
        }
        await prepareVerification()
        guard let verifyModel, verifyModel.isActive else { return }
        navigator.navigate(to: .verify)
        await verifyModel.activate()
    }

    func prepareVerification() async {
        guard let context = await verificationContext() else { return }
        if verifyModel?.context != context || verifyModel?.isActive != true {
            verifyModel?.cancel()
            let mail: (@MainActor () async -> SignedVerificationInput?)?
            if let mock = source as? MockDataSource {
                mail = {
                    guard let events = try? await mock.inbox(),
                        case .verification(_, _, _, let input) = events.last(where: {
                            if case .verification(_, let to, _, let input) = $0 {
                                return to == context.email && input.id == context.accountID
                            }
                            return false
                        })
                    else { return nil }
                    return input
                }
            } else {
                mail = nil
            }
            verifyModel = VerifyEmailModel(
                context: context, source: source,
                current: { [weak self] in await self?.verificationContext() },
                persist: { [weak self] context in
                    guard let self, let snapshot = await nativeSession.controller.activeSession(),
                        snapshot.epoch == context.epoch, snapshot.session.accountId == context.accountID
                    else { return false }
                    await nativeSession.sync?.stop()
                    return try await nativeSession.controller.confirmEmailVerification(
                        expected: snapshot, email: context.email)
                },
                route: { [weak self] in
                    guard let self else { return }
                    await nativeSession.routeAcceptedSession(navigator: navigator, verification: verification)
                },
                discard: { [weak self] in
                    guard let self else { return }
                    #if DEBUG
                        if authUITestEnabled,
                            ProcessInfo.processInfo.environment["CF_AUTH_TEST_VERIFY_STATE"] == "signOutError"
                        {
                            throw DataFailure.offline
                        }
                    #endif
                    guard let snapshot = await nativeSession.controller.activeSession(),
                        snapshot.epoch == context.epoch,
                        snapshot.session.accountId == context.accountID, await verificationContext() == context
                    else { return }
                    _ = try await nativeSession.controller.signOut(expected: snapshot, discardPending: true)
                    guard await nativeSession.controller.presence == .signedOut else { return }
                    if verifyModel?.context == context { verifyModel = nil }
                    if navigator.route == .verify { navigator.navigate(to: .signIn) }
                },
                mail: mail)
        }
        if case .verify(let input) = pendingVerification {
            pendingVerification = nil
            verifyModel?.receiveLink(input)
        }
    }

}
