import AppCore
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var launchProcess = LaunchProcessState()
    var nativeSession: NativeSessionController?
    var authServices: AuthSessionServices?
    let navigator = RootNavigator()

    func verificationRequired(epoch: UInt64) async {
        guard let nativeSession, await nativeSession.controller.epoch == epoch else { return }
        navigator.navigate(to: .verify)
    }
}
