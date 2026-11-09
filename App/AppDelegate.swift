import AppCore
import LocalStore
import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var launchProcess = LaunchProcessState()
    var nativeSession: NativeSessionController?
    var authServices: AuthSessionServices?
    weak var authWindow: UIWindow?
    let navigator = RootNavigator()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let intent = PendingLaunchIntent(
            notification: .capture(
                identifier: response.notification.request.identifier, actionIdentifier: response.actionIdentifier,
                userInfo: response.notification.request.content.userInfo, userText: nil))
        for scene in UIApplication.shared.connectedScenes {
            (scene.delegate as? SceneDelegate)?.receiveReminderIntent(intent)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) { completionHandler([.banner, .list]) }

    func verificationRequired(epoch: UInt64) async {
        guard let nativeSession, await nativeSession.controller.epoch == epoch else { return }
        guard let database = await nativeSession.accounts.activeDatabase(),
            let account = try? await AccountRepository(database: database).account(), !account.hasVerifiedEmail,
            await nativeSession.controller.epoch == epoch
        else { return }
        await authServices?.prepareVerification()
        guard await nativeSession.controller.epoch == epoch,
            await authServices?.verificationContext(requireUnverified: true)?.epoch == epoch,
            authServices?.verifyModel?.isActive == true
        else { return }
        navigator.navigate(to: .verify)
    }
}
