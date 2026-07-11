import SwiftUI

@main
struct EspTempApp: App {
    init() {
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
