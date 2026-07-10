import Foundation
import Observation

/// Observable view-model shared by the iOS and watchOS apps.
/// Loads the latest temperature/humidity and recent history from Adafruit IO.
@Observable
@MainActor
public final class TemperatureStore {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var temperature: FeedReading?
    public private(set) var humidity: FeedReading?
    public private(set) var history: [FeedReading] = []
    public private(set) var state: LoadState = .idle
    public private(set) var hasCredentials: Bool = CredentialStore.load() != nil

    public init() {}

    public func refresh() async {
        guard let creds = CredentialStore.load() else {
            hasCredentials = false
            state = .failed("Ingen Adafruit IO-innlogging lagret ennå.")
            return
        }
        hasCredentials = true
        state = .loading
        let client = AdafruitIOClient(username: creds.username, apiKey: creds.apiKey)
        do {
            async let temp = client.latest(feed: creds.temperatureFeed)
            async let hum = try? client.latest(feed: creds.humidityFeed)
            async let hist = try? client.history(feed: creds.temperatureFeed, limit: 200)
            temperature = try await temp
            humidity = await hum
            history = await hist ?? []
            state = .loaded
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    public func reloadCredentialFlag() {
        hasCredentials = CredentialStore.load() != nil
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case AdafruitIOError.http(let code): return "HTTP-feil \(code) (sjekk nøkkel/feed)."
        case AdafruitIOError.empty: return "Feeden har ingen verdi ennå."
        case AdafruitIOError.badURL: return "Ugyldig brukernavn/feed."
        default: return error.localizedDescription
        }
    }
}
