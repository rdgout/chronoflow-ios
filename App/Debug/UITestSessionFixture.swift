#if DEBUG
    import AppCore
    import Foundation

    @MainActor enum UITestSessionFixture {
        static func route(native: NativeSessionController?, navigator: RootNavigator) async {
            guard let native, case .signedIn = await native.readiness.session() else {
                navigator.navigate(to: .welcome)
                return
            }
            await native.readiness.allowFirstLoad()
            let gate = await native.readiness.gate()
            navigator.navigate(to: gate.route)
        }

        static func tearDown(native: NativeSessionController?, auth: AuthSessionServices?) async throws {
            await auth?.stopUITestSession()
            guard let native else { return }
            await native.stopObserving()
            _ = try await native.controller.signOut(discardPending: true, unauthorized: true)
            await native.sync?.stop()
            try await native.accounts.close()
        }
    }
#endif
