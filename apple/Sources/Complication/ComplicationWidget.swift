import WidgetKit
import SwiftUI

// TempEntry, TempProvider, tempColor, tempSymbol and staleWindow live in
// Sources/Shared/TempWidgetShared.swift (shared with the iOS widget).

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
