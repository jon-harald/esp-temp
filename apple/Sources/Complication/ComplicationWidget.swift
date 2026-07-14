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

/// Ring fills over this window since the last reading; resets when fresher data arrives.
private let staleWindow: TimeInterval = 30 * 60

/// Temperature colour bands: green 12–20, orange 8–12 & 20–27, red <8 & >27.
/// Renders literally in full-colour contexts (Smart Stack, gallery); on an
/// accented watch face it degrades to the face tint — the symbol below carries
/// a coarse cue in that case.
private func tempColor(_ c: Double?) -> Color {
    guard let c else { return .gray }
    switch c {
    case ..<8:  return .red
    case ..<12: return .orange
    case ..<20: return .green
    case ...27: return .orange
    default:    return .red
    }
}

/// A shape cue that survives monochrome rendering.
private func tempSymbol(_ c: Double?) -> String {
    guard let c else { return "thermometer.medium" }
    if c < 12 { return "thermometer.low" }
    if c < 20 { return "thermometer.medium" }
    return "thermometer.high"
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TempEntry

    private var short: String { entry.temperature.map { String(format: "%.0f°", $0) } ?? "–" }
    private var precise: String { entry.temperature.map { String(format: "%.1f°", $0) } ?? "–" }
    private var color: Color { tempColor(entry.temperature) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular

#if os(watchOS)
        case .accessoryCorner:
            Text(short)
                .font(.system(.title2, design: .rounded))
                .foregroundStyle(color)
                .widgetCurvesContent()
                .widgetLabel { freshnessText }
#endif

        case .accessoryInline:
            inline

        case .accessoryRectangular:
            rectangular

        default:
            Text(precise)
        }
    }

    // Ring = time since last reading (self-updating); centre = temperature, colour by band.
    @ViewBuilder private var circular: some View {
        if let readingDate = entry.readingDate {
            ProgressView(
                timerInterval: readingDate...readingDate.addingTimeInterval(staleWindow),
                countsDown: false
            ) {
                EmptyView()
            } currentValueLabel: {
                Text(short).foregroundStyle(color)
            }
            .progressViewStyle(.circular)
            .tint(color)
        } else {
            Gauge(value: 0, in: 0...1) { Text("–") } currentValueLabel: { Text("–") }
                .gaugeStyle(.accessoryCircular)
        }
    }

    @ViewBuilder private var inline: some View {
        if let readingDate = entry.readingDate {
            // Inline is a single monochrome line; the relative part self-updates.
            Text("🌡 \(precise) · ") + Text(readingDate, style: .relative)
        } else {
            Text("🌡 \(precise)")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(precise, systemImage: tempSymbol(entry.temperature))
                .font(.system(.title2, design: .rounded))
                .foregroundStyle(color)
            if let readingDate = entry.readingDate {
                (Text("Oppdatert ") + Text(readingDate, style: .relative) + Text(" siden"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ingen data").font(.caption2).foregroundStyle(.secondary)
            }
            if let h = entry.humidity {
                Text("\(Int(h.rounded())) % RF").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var freshnessText: some View {
        if let readingDate = entry.readingDate {
            Text(readingDate, style: .relative)
        } else {
            Text("–")
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
