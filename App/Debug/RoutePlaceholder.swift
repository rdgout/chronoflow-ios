#if DEBUG
    import AppCore
    import SwiftUI
    import LocalStore
    import UIKit

    struct RoutePlaceholder: View {
        let route: Route
        @State private var cacheStatus = "pending"
        @State private var signingOut = false

        private var authTestEnabled: Bool {
            (UIApplication.shared.delegate as? AppDelegate)?.authServices?.authUITestEnabled == true
        }

        var body: some View {
            Text(String(format: String(localized: "Debug route: %@"), route.rawValue))
                .accessibilityIdentifier("route.\(route.rawValue)")
                .accessibilityValue(authTestEnabled ? cacheStatus : "")
                .onTapGesture {
                    guard authTestEnabled, !signingOut,
                        let native = (UIApplication.shared.delegate as? AppDelegate)?.nativeSession
                    else { return }
                    signingOut = true
                    Task {
                        do { _ = try await native.controller.signOut(discardPending: true) } catch {
                            cacheStatus = "sign-out-failed"
                        }
                        signingOut = false
                    }
                }
                .task {
                    guard authTestEnabled,
                        let native = (UIApplication.shared.delegate as? AppDelegate)?.nativeSession,
                        let database = await native.accounts.activeDatabase()
                    else { return }
                    do {
                        for try await account in try await AccountRepository(database: database).values() {
                            if account?.syncedAt != nil {
                                cacheStatus = "cached"
                                return
                            }
                        }
                    } catch { cacheStatus = "cache-unavailable" }
                }
        }
    }
#endif
