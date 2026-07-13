import Foundation
import Observation
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

/// Owns the FCM registration token and keeps it in sync with Firestore under the
/// signed-in user (`users/{uid}/fcmTokens/{token}`). iOS-only (lives in Sources/App).
@Observable
@MainActor
final class PushService {
    static let shared = PushService()
    private init() {}

    private(set) var fcmToken: String?
    /// Set when the user taps an alert; the UI navigates to this device then clears it.
    var pendingDeepLinkDeviceId: String?

    /// Ask for notification permission, then register with APNs (→ FCM token).
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("[push] authorization error: \(error.localizedDescription)")
        }
    }

    func setToken(_ token: String) {
        fcmToken = token
        Task { await uploadCurrentToken() }
    }

    /// Write the current token for the current user. Safe to call repeatedly.
    func uploadCurrentToken() async {
        guard let token = fcmToken, let uid = Auth.auth().currentUser?.uid else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("fcmTokens").document(token)
                .setData([
                    "platform": "ios",
                    "appVersion": version,
                    "createdAt": FieldValue.serverTimestamp(),
                    "lastSeenAt": FieldValue.serverTimestamp(),
                ], merge: true)
        } catch {
            print("[push] token upload failed: \(error.localizedDescription)")
        }
    }

    /// Remove the token from Firestore + invalidate it. MUST be called while still
    /// signed in (needs the uid), i.e. before `Auth.signOut()`.
    func removeCurrentToken() async {
        if let token = fcmToken, let uid = Auth.auth().currentUser?.uid {
            try? await Firestore.firestore()
                .collection("users").document(uid)
                .collection("fcmTokens").document(token).delete()
        }
        try? await Messaging.messaging().deleteToken()
        fcmToken = nil
    }
}
