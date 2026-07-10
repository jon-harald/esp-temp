import Foundation
import Security

public enum AppConfig {
    /// App Group used to share settings + credentials between the app, watch app and complication.
    /// Must match the App Groups capability in every target's entitlements.
    public static let appGroup = "group.no.brathen.esptemp"
    public static let defaultTemperatureFeed = "temperature"
    public static let defaultHumidityFeed = "humidity"
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

/// Stores non-secret settings in the App Group's shared UserDefaults and the
/// Adafruit IO key in the Keychain (shared via the App Group access group).
public enum CredentialStore {
    private static let kUsername = "aio.username"
    private static let kTempFeed = "aio.tempFeed"
    private static let kHumFeed = "aio.humFeed"
    private static let keychainAccount = "aio.apiKey"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroup) ?? .standard
    }

    public static func load() -> Credentials? {
        guard let username = defaults.string(forKey: kUsername), !username.isEmpty,
              let apiKey = Keychain.read(account: keychainAccount), !apiKey.isEmpty else {
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
        defaults.set(credentials.temperatureFeed, forKey: kTempFeed)
        defaults.set(credentials.humidityFeed, forKey: kHumFeed)
        Keychain.write(credentials.apiKey, account: keychainAccount)
    }

    public static func clear() {
        [kUsername, kTempFeed, kHumFeed].forEach { defaults.removeObject(forKey: $0) }
        Keychain.delete(account: keychainAccount)
    }
}

/// Tiny Keychain wrapper. Items are shared across targets via the App Group access group.
public enum Keychain {
    /// Using the App Group id as the keychain access group lets the app + extensions
    /// read the same item. Requires the App Groups capability in each target.
    private static var accessGroup: String { AppConfig.appGroup }

    public static func write(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    public static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
