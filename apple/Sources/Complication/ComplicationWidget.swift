import WidgetKit
import SwiftUI

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
            // Refresh roughly every 20 minutes (watchOS budgets background refreshes).
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

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TempEntry

    private var short: String { entry.temperature.map { String(format: "%.0f°", $0) } ?? "–" }
    private var precise: String { entry.temperature.map { String(format: "%.1f°", $0) } ?? "–" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.temperature ?? 0, in: -10...40) {
                Text("°C")
            } currentValueLabel: {
                Text(short)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.orange)

#if os(watchOS)
        case .accessoryCorner:
            Text(short)
                .font(.system(.title2, design: .rounded))
                .widgetCurvesContent()
                .widgetLabel("Temperatur")
#endif

        case .accessoryInline:
            Text("🌡 \(precise)")

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Temperatur").font(.caption).foregroundStyle(.secondary)
                Text(precise).font(.system(.title2, design: .rounded))
                if let h = entry.humidity {
                    Text("\(Int(h.rounded())) % RF").font(.caption2).foregroundStyle(.secondary)
                }
            }

        default:
            Text(precise)
        }
    }
}

struct EspTempComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EspTempComplication", provider: TempProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Temperatur")
        .description("Siste temperatur fra sensoren.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct EspTempComplicationBundle: WidgetBundle {
    var body: some Widget {
        EspTempComplication()
    }
}
