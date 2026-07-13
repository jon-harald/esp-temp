import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// iOS-only. Configures Firebase and bridges APNs ⇄ FCM ⇄ UNUserNotificationCenter.
/// Attached via `@UIApplicationDelegateAdaptor` in `EspTempApp`. Its
/// `didFinishLaunchingWithOptions` runs before the first view, so it is the one
/// safe place to call `FirebaseApp.configure()`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Redundant while FCM swizzling is on, but explicit is more robust.
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[push] APNs registration failed: \(error.localizedDescription)")
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in PushService.shared.setToken(fcmToken) }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Show alerts even while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // Deep-link to the tapped device's thresholds.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let deviceId = info["deviceId"] as? String {
            await MainActor.run { PushService.shared.pendingDeepLinkDeviceId = deviceId }
        }
    }
}
