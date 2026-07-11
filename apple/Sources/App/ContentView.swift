import SwiftUI
import Charts
import WidgetKit

struct ContentView: View {
    @State private var store = TemperatureStore()
    @State private var showingSettings = false
    @State private var showBatteryVolts = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.hasCredentials {
                    needsSetup
                } else {
                    content
                }
            }
            .navigationTitle("Temperatur")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: {
                store.reloadCredentialFlag()
                Task { await store.refresh() }
            }) {
                SettingsView()
            }
            .task { await store.refresh() }
            .refreshable { await store.refresh() }
        }
    }

    private var needsSetup: some View {
        ContentUnavailableView {
            Label("Sett opp Adafruit IO", systemImage: "key.horizontal")
        } description: {
            Text("Legg inn brukernavn og AIO-nøkkel for å hente data.")
        } actions: {
            Button("Åpne innstillinger") { showingSettings = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var content: some View {
        List {
            Section {
                HStack {
                    readingTile(title: "Temperatur",
                                value: store.temperature.map { String(format: "%.1f °C", $0.value) } ?? "–",
                                systemImage: "thermometer.medium",
                                tint: .orange)
                    readingTile(title: "Fuktighet",
                                value: store.humidity.map { String(format: "%.0f %%", $0.value) } ?? "–",
                                systemImage: "humidity",
                                tint: .blue)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    withAnimation(.snappy) { showBatteryVolts.toggle() }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: batterySymbol)
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(batteryTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Batteri").font(.caption).foregroundStyle(.secondary)
                            Text(batteryText)
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .contentTransition(.numericText())
                        }
                        Spacer()
                        Image(systemName: "hand.tap")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } footer: {
                Text(showBatteryVolts ? "Trykk for prosent" : "Trykk for spenning (V)")
            }

            if !store.history.isEmpty {
                Section("Siste 24 t") {
                    Chart(store.history) { reading in
                        LineMark(
                            x: .value("Tid", reading.createdAt),
                            y: .value("°C", reading.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.orange)
                    }
                    .frame(height: 200)
                }
            }

            if case .failed(let message) = store.state {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            if let updated = store.temperature?.createdAt {
                Section {
                    LabeledContent("Sist oppdatert", value: updated.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var batteryText: String {
        if showBatteryVolts {
            return store.batteryVoltage.map { String(format: "%.2f V", $0.value) } ?? "–"
        }
        guard let p = store.batteryPercent?.value else { return "–" }
        return "\(Int(min(100, max(0, p.rounded())))) %"
    }

    private var batteryFraction: Double? {
        store.batteryPercent.map { min(100, max(0, $0.value)) / 100 }
    }

    private var batterySymbol: String {
        guard let f = batteryFraction else { return "battery.0percent" }
        switch f {
        case ..<0.1: return "battery.0percent"
        case ..<0.375: return "battery.25percent"
        case ..<0.625: return "battery.50percent"
        case ..<0.875: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var batteryTint: Color {
        guard let f = batteryFraction else { return .secondary }
        switch f {
        case ..<0.2: return .red
        case ..<0.4: return .orange
        default: return .green
        }
    }

    private func readingTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

#Preview {
    ContentView()
}
