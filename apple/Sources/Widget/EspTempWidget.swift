import WidgetKit
import SwiftUI

// Shares TempEntry / TempProvider / tempColor / tempSymbol / staleWindow with the
// watch complication via Sources/Shared/TempWidgetShared.swift.

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TempEntry

    private var short: String { entry.temperature.map { String(format: "%.0f°", $0) } ?? "–" }
    private var precise: String { entry.temperature.map { String(format: "%.1f°", $0) } ?? "–" }
    private var color: Color { tempColor(entry.temperature) }

    var body: some View {
        switch family {
        case .systemSmall:        small
        case .systemMedium:       medium
        case .accessoryCircular:  circular
        case .accessoryRectangular: rectangular
        case .accessoryInline:    inline
        default:                  small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Temperatur", systemImage: tempSymbol(entry.temperature))
                .font(.caption2).foregroundStyle(.secondary)
            Text(precise)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)
            freshness.font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Temperatur", systemImage: tempSymbol(entry.temperature))
                    .font(.caption).foregroundStyle(.secondary)
                Text(precise)
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                freshness.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let h = entry.humidity {
                Label("\(Int(h.rounded())) %", systemImage: "humidity")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Lock Screen ring: fills with time since last reading; centre = temperature.
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

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(precise, systemImage: tempSymbol(entry.temperature))
                .font(.headline)
                .foregroundStyle(color)
            freshness.font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var inline: some View {
        if let readingDate = entry.readingDate {
            Text("🌡 \(precise) · ") + Text(readingDate, style: .relative)
        } else {
            Text("🌡 \(precise)")
        }
    }

    @ViewBuilder private var freshness: some View {
        if let readingDate = entry.readingDate {
            Text("Oppdatert ") + Text(readingDate, style: .relative) + Text(" siden")
        } else {
            Text("Ingen data")
        }
    }
}

struct EspTempWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EspTempWidget", provider: TempProvider()) { entry in
            WidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Temperatur")
        .description("Siste temperatur fra sensoren.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct EspTempWidgetBundle: WidgetBundle {
    var body: some Widget {
        EspTempWidget()
    }
}
