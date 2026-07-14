import Foundation
import SwiftUI
import WidgetKit

/// Shared building blocks for the watchOS complication and the iOS widget.
/// Compiled into every target (harmless in the app, which just doesn't use it),
/// so the temperature colour bands live in exactly one place.

struct TempEntry: TimelineEntry {
    let date: Date
    let temperature: Double?
    let humidity: Double?
    let readingDate: Date?
}

struct TempProvider: TimelineProvider {
    func placeholder(in context: Context) -> TempEntry {
        TempEntry(date: .now, temperature: 21.5, humidity: 40, readingDate: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (TempEntry) -> Void) {
        Task { completion(await fetchEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TempEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            // WidgetKit budgets background refreshes to roughly this cadence.
            let next = Date.now.addingTimeInterval(20 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetchEntry() async -> TempEntry {
        guard let creds = CredentialStore.load() else {
            return TempEntry(date: .now, temperature: nil, humidity: nil, readingDate: nil)
        }
        let client = AdafruitIOClient(username: creds.username, apiKey: creds.apiKey)
        let temp = try? await client.latest(feed: creds.temperatureFeed)
        let hum = try? await client.latest(feed: creds.humidityFeed)
        return TempEntry(date: .now, temperature: temp?.value, humidity: hum?.value, readingDate: temp?.createdAt)
    }
}

/// The ring/gauge freshness indicator fills over this window since the last reading.
let staleWindow: TimeInterval = 30 * 60

/// Temperature colour bands: green 12–20, orange 8–12 & 20–27, red <8 & >27.
/// Renders literally in full-colour contexts (Smart Stack, gallery, home screen);
/// on an accented Lock Screen / watch face it degrades to the tint — the symbol
/// below carries a coarse cue there.
func tempColor(_ c: Double?) -> Color {
    guard let c else { return .gray }
    switch c {
    case ..<8:  return .red
    case ..<12: return .orange
    case ..<20: return .green
    case ...27: return .orange
    default:    return .red
    }
}

/// Coarse shape cue that survives monochrome rendering.
func tempSymbol(_ c: Double?) -> String {
    guard let c else { return "thermometer.medium" }
    if c < 12 { return "thermometer.low" }
    if c < 20 { return "thermometer.medium" }
    return "thermometer.high"
}
