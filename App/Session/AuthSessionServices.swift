import AppCore
import Auth
import DataAccess
import Foundation
import LocalStore
import Observation
import TripWizard
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
    private let verificationLinks = VerificationLinkInbox()
    @ObservationIgnored private var verificationSubscription: Task<Void, Never>?
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
                UITestRuntime.arguments.contains("-cf.twoFactorServerFailure")
            {
                Task { await mock.failNext(method: .completeTwoFactor, error: .server(status: 503)) }
            }
            if services.factory.source == .mock, let mock = source as? MockDataSource {
                if services.authUITestEnabled,
                    let failure = UITestRuntime.environment["CF_AUTH_TEST_RESET_FAILURE"]
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
                    let failure = UITestRuntime.environment["CF_AUTH_TEST_SIGNUP_FAILURE"]
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
                    let failure = AuthUITestConfiguration(environment: UITestRuntime.environment)?
                        .verificationResendFailure
                {
                    Task {
                        await mock.failNext(method: .resendVerificationEmail, error: failure)
                    }
                }
                if UITestRuntime.arguments.contains("-cf.forgotServerFailure") {
                    Task { await mock.failNext(method: .requestPasswordReset, error: .server(status: 503)) }
                } else if UITestRuntime.arguments.contains("-cf.forgotThrottleFailure") {
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
            claim: { await native.guestWizardStore.claim(secrets: native.guestSecrets) },
            guestReviewExpired: { try? await native.guestWizardStore.reviewExpired(claim: $0) },
            accepted: { result, method in
                try await native.routeAcceptedSession(
                    result, method: method, navigator: navigator, verification: verification)
            })
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
        verificationSubscription = Task { [weak self, controller = native.controller] in
            for await _ in await controller.updates() {
                guard !Task.isCancelled, let self else { return }
                await synchronizeVerificationSession()
            }
        }
    }
    func verificationContext(requireUnverified: Bool = false) async -> VerificationContext? {
        guard let snapshot = await nativeSession.controller.activeSession(),
            let database = await nativeSession.accounts.activeDatabase(),
            let account = try? await AccountRepository(database: database).account(),
            account.id == snapshot.session.accountId,
            !requireUnverified || !account.hasVerifiedEmail,
            await nativeSession.controller.activeSession() == snapshot
        else { return nil }
        return VerificationContext(accountID: account.id, email: account.email, epoch: snapshot.epoch)
    }

    func receiveVerificationLink(_ input: SignedVerificationInput?) async {
        guard await synchronizeVerificationSession(), verificationLinks.receive(input) else { return }
        if await nativeSession.controller.presence == .signedOut {
            model.clearSecrets()
            navigator.navigate(to: .signIn)
            return
        }
        await prepareVerification()
        guard let verifyModel, verifyModel.isActive,
            await verificationContext(requireUnverified: true) == verifyModel.context
        else { return }
        navigator.navigate(to: .verify)
        await verifyModel.activate()
    }

    func prepareVerification() async {
        guard await synchronizeVerificationSession(),
            let context = await verificationContext(requireUnverified: true)
        else { return }
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
                            UITestRuntime.environment["CF_AUTH_TEST_VERIFY_STATE"] == "signOutError"
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
        if let input = verificationLinks.take(for: context) {
            verifyModel?.receiveLink(input)
        }
    }

    @discardableResult private func synchronizeVerificationSession() async -> Bool {
        let controller = nativeSession.controller
        let epoch = await controller.epoch
        guard let presence = await controller.presence else { return false }
        var verified = false
        if case .signedIn(let id) = presence {
            guard let snapshot = await controller.activeSession(), snapshot.epoch == epoch,
                let database = await nativeSession.accounts.activeDatabase(),
                let account = try? await AccountRepository(database: database).account(), account.id == id
            else { return false }
            verified = account.hasVerifiedEmail
        }
        guard await controller.epoch == epoch, await controller.presence == presence else { return false }
        verificationLinks.sessionChanged(presence: presence, epoch: epoch, hasVerifiedEmail: verified)
        if let verifyModel, verifyModel.context.epoch != epoch {
            verifyModel.cancel()
            self.verifyModel = nil
        }
        return true
    }

    #if DEBUG
        func prepareUITestRoute(_ test: AuthUITestConfiguration, navigator: RootNavigator) async throws {
            guard test.fastLaunch else { return }
            if let board = UITestRuntime.environment["CF_GUEST_RECOVERY_BOARD"] {
                var draft = try await nativeSession.guestWizardStore.start()
                draft = GuestWizardBoardSeed.draft(draft, board: board, locale: Locale(identifier: "en_GB"))
                try await nativeSession.guestWizardStore.persist(draft)
                return
            }
            if UITestRuntime.environment["CF_GUEST_WIZARD"] == "1" {
                navigator.navigate(to: .guestWizard)
                return
            }
            switch test.auditScreen {
            case "sign-in":
                navigator.navigate(to: .signIn)
            case "sign-up":
                navigator.navigate(to: .signIn)
                model.navigation.push(.signUp)
            case "forgot":
                navigator.navigate(to: .signIn)
                model.navigation.forgot()
            case "reset" where test.auditState != "expired":
                try await source.requestPasswordReset(email: MockScenarioValues.demoEmail)
                guard case .reset(let link)? = await model.mockMail?(MockScenarioValues.demoEmail) else {
                    throw AppServices.Failure.invalidReadiness
                }
                navigator.navigate(to: .signIn)
                model.openReset(link)
            default: break
            }
        }

        func stopUITestSession() async {
            model.clearSecrets()
            verifyModel?.cancel()
            verificationSubscription?.cancel()
            await verificationSubscription?.value
            verificationSubscription = nil
        }
    #endif

    deinit { verificationSubscription?.cancel() }

    func makeGuestWizard(locale: Locale) async throws -> MemberWizardModel {
        guard await nativeSession.controller.presence == .signedOut else { throw CancellationError() }
        let store = nativeSession.guestWizardStore
        var draft = try await store.start()
        if draft.state.signingIn == true {
            draft.state.signingIn = false
            draft.state.revision += 1
            try await store.persist(draft)
        }
        #if DEBUG
            let board =
                authUITestEnabled && UITestRuntime.environment["CF_GUEST_WIZARD"] == "1"
                ? UITestRuntime.environment["CF_WIZARD_BOARD_CAPTURE"] : nil
            if let board {
                draft = GuestWizardBoardSeed.draft(draft, board: board, locale: locale)
                try await store.persist(draft)
            }
        #endif
        try Task.checkCancellation()
        guard await nativeSession.controller.presence == .signedOut else { throw CancellationError() }
        let generation = GuestWizardGeneration(
            source: source, secrets: nativeSession.guestSecrets,
            deviceIdentity: DeviceIdentityStore(persistence: DevicePreferences()))
        let wizard = MemberWizardModel(
            draft: draft, store: store, search: AirportSearchService(source: source), generation: generation)
        #if DEBUG
            if let board { WizardBoardCaptureSeed.freeze(wizard, board: board) }
        #endif
        return wizard
    }
}
