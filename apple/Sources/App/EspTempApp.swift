import SwiftUI

@main
struct EspTempApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // AuthManager.init() must NOT touch Firebase (it runs before configure());
    // the auth listener is attached in RootView's .task via auth.start().
    @State private var auth = AuthManager()

    init() {
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
        }
    }
}
