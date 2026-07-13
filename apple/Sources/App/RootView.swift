import SwiftUI

/// Gates the app on Firebase Auth: sign-in screen when signed out, dashboard when in.
struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            switch auth.phase {
            case .loading:
                ProgressView("Laster …")
            case .signedOut:
                SignInView()
            case .signedIn:
                ContentView()
            }
        }
        .task {
            // Runs after didFinishLaunching (Firebase is configured); attach the
            // auth state listener exactly once.
            auth.start()
        }
    }
}
