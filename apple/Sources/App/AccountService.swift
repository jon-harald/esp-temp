import Foundation
import Observation
import FirebaseFunctions

/// Resolves the signed-in login (uid) to its canonical account. "Same verified
/// email ⇒ same account" is enforced server-side by the `resolveAccount` Cloud
/// Function (europe-west1), which unifies the user's Apple/Google/password logins
/// and refreshes device membership. iOS-only (Sources/App).
///
/// Called once per sign-in from `AuthManager.apply(user:)`. Until the email is
/// verified the function returns `needsEmailVerification` and grants no account,
/// so a fresh email/password sign-up sees no devices until it confirms the link.
@Observable
@MainActor
final class AccountService {
    static let shared = AccountService()
    private init() {}

    private(set) var accountId: String?
    private(set) var needsEmailVerification = false

    @ObservationIgnored private let functions = Functions.functions(region: "europe-west1")

    func resolve() async {
        do {
            let result = try await functions.httpsCallable("resolveAccount").call()
            let data = result.data as? [String: Any] ?? [:]
            accountId = data["accountId"] as? String
            needsEmailVerification = (data["needsEmailVerification"] as? Bool) ?? false
        } catch {
            print("[account] resolve failed: \(error.localizedDescription)")
        }
    }

    func clear() {
        accountId = nil
        needsEmailVerification = false
    }
}
