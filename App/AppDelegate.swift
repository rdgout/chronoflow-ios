import AppCore
import LocalStore
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var launchProcess = LaunchProcessState()
    var nativeSession: NativeSessionController?
    var authServices: AuthSessionServices?
    weak var authWindow: UIWindow?
    let navigator = RootNavigator()

    func verificationRequired(epoch: UInt64) async {
        guard let nativeSession, await nativeSession.controller.epoch == epoch else { return }
        guard let database = await nativeSession.accounts.activeDatabase(),
            let account = try? await AccountRepository(database: database).account(), !account.hasVerifiedEmail,
            await nativeSession.controller.epoch == epoch
        else { return }
        await authServices?.prepareVerification()
        guard await nativeSession.controller.epoch == epoch else { return }
        navigator.navigate(to: .verify)
    }
}
