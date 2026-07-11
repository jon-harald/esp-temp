import Foundation

public enum AppConfig {
    /// App Group used to share settings + credentials between the app, watch app and complication.
    /// Must match the App Groups capability in every target's entitlements.
    public static let appGroup = "group.no.brathen.esptemp"
    public static let defaultTemperatureFeed = "temperature"
    public static let defaultHumidityFeed = "humidity"
    public static let batteryPercentFeed = "esp-battery-pct"
    public static let batteryVoltageFeed = "esp-battery-v"
}

public struct Credentials: Sendable, Equatable {
    public var username: String
    public var apiKey: String
    public var temperatureFeed: String
    public var humidityFeed: String

    public init(username: String,
                apiKey: String,
                temperatureFeed: String = AppConfig.defaultTemperatureFeed,
                humidityFeed: String = AppConfig.defaultHumidityFeed) {
        self.username = username
        self.apiKey = apiKey
        self.temperatureFeed = temperatureFeed
        self.humidityFeed = humidityFeed
    }
}

/// Stores settings + the Adafruit IO key in the App Group's shared UserDefaults so the app,
/// watch app and complication all read the same values. The container is OS-protected; for a
/// read-only temperature key this is acceptable (can be hardened to a shared Keychain later).
public enum CredentialStore {
    private static let kUsername = "aio.username"
    private static let kApiKey = "aio.apiKey"
    private static let kTempFeed = "aio.tempFeed"
    private static let kHumFeed = "aio.humFeed"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroup) ?? .standard
    }

    public static func load() -> Credentials? {
        guard let username = defaults.string(forKey: kUsername), !username.isEmpty,
              let apiKey = defaults.string(forKey: kApiKey), !apiKey.isEmpty else {
            return nil
        }
        return Credentials(
            username: username,
            apiKey: apiKey,
            temperatureFeed: defaults.string(forKey: kTempFeed) ?? AppConfig.defaultTemperatureFeed,
            humidityFeed: defaults.string(forKey: kHumFeed) ?? AppConfig.defaultHumidityFeed
        )
    }

    public static func save(_ credentials: Credentials) {
        defaults.set(credentials.username, forKey: kUsername)
        defaults.set(credentials.apiKey, forKey: kApiKey)
        defaults.set(credentials.temperatureFeed, forKey: kTempFeed)
        defaults.set(credentials.humidityFeed, forKey: kHumFeed)
    }

    public static func clear() {
        [kUsername, kApiKey, kTempFeed, kHumFeed].forEach { defaults.removeObject(forKey: $0) }
    }
}
