import SwiftUI

@main
struct EspTempWatchApp: App {
    init() {
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
