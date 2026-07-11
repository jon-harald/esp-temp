import Foundation
import WidgetKit
#if canImport(WatchConnectivity)
import WatchConnectivity

/// Syncs Adafruit IO credentials from the iPhone to the paired Apple Watch.
/// App Groups only share within one device, so the watch app + complication need the
/// key delivered over WatchConnectivity. The phone pushes the latest creds via
/// `updateApplicationContext` (delivered even in the background); the watch also asks
/// for them on launch if it has none.
public final class WatchSync: NSObject {
    public static let shared = WatchSync()
    private override init() { super.init() }

    public func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Phone → watch: push the current credentials as the latest app context.
    public func sendCredentials() {
        guard WCSession.isSupported(), let creds = CredentialStore.load() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(Self.encode(creds))
    }

    fileprivate static func encode(_ c: Credentials) -> [String: Any] {
        ["username": c.username, "apiKey": c.apiKey,
         "tempFeed": c.temperatureFeed, "humFeed": c.humidityFeed]
    }

    fileprivate static func apply(_ payload: [String: Any]) {
        guard let username = payload["username"] as? String, !username.isEmpty,
              let apiKey = payload["apiKey"] as? String, !apiKey.isEmpty else { return }
        CredentialStore.save(Credentials(
            username: username,
            apiKey: apiKey,
            temperatureFeed: payload["tempFeed"] as? String ?? AppConfig.defaultTemperatureFeed,
            humidityFeed: payload["humFeed"] as? String ?? AppConfig.defaultHumidityFeed
        ))
        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .credentialsUpdated, object: nil)
        }
    }
}

extension WatchSync: WCSessionDelegate {
    public func session(_ session: WCSession,
                        activationDidCompleteWith activationState: WCSessionActivationState,
                        error: Error?) {
        guard activationState == .activated else { return }
        #if os(iOS)
        // Always publish current creds so the watch has the latest context.
        if let creds = CredentialStore.load() {
            try? session.updateApplicationContext(WatchSync.encode(creds))
        }
        #else
        // watchOS: pull from the phone if we don't have creds yet.
        if CredentialStore.load() == nil, session.isReachable {
            session.sendMessage(["request": "credentials"],
                                replyHandler: { WatchSync.apply($0) },
                                errorHandler: nil)
        }
        #endif
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        WatchSync.apply(applicationContext)
    }

    #if os(iOS)
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                        replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(CredentialStore.load().map(WatchSync.encode) ?? [:])
    }
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}

public extension Notification.Name {
    static let credentialsUpdated = Notification.Name("credentialsUpdated")
}
#endif
