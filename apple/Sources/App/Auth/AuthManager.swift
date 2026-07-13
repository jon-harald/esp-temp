import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import FirebaseAuth

/// Firebase Auth state + sign-in flows. iOS-only (Sources/App). `init()` deliberately
/// does no Firebase work — `start()` (called from RootView.task, after configure())
/// attaches the state listener.
@Observable
@MainActor
final class AuthManager {
    enum Phase { case loading, signedOut, signedIn }

    private(set) var phase: Phase = .loading
    private(set) var user: User?
    var errorMessage: String?

    private var listenerHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    func start() {
        guard listenerHandle == nil else { return }
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.apply(user: user) }
        }
    }

    private func apply(user: User?) {
        self.user = user
        phase = user == nil ? .signedOut : .signedIn
        if user != nil {
            Task {
                await PushService.shared.requestAuthorization()
                await PushService.shared.uploadCurrentToken()
            }
        }
    }

    var email: String? { user?.email }

    // MARK: - Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleSignInWithApple(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce = currentNonce,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple-innlogging feilet (mangler token)."
                return
            }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: credential.fullName
            )
            do {
                try await Auth.auth().signIn(with: firebaseCredential)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Email / password

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        errorMessage = nil
        do {
            try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign out

    func signOut() async {
        // Delete the FCM token while we still have the uid, then sign out.
        await PushService.shared.removeCurrentToken()
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Nonce helpers (per Firebase's Sign in with Apple guide)

    private func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed: \(status)")
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
