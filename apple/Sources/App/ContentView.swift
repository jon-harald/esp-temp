import SwiftUI
import Charts
import WidgetKit

struct ContentView: View {
    @State private var store = TemperatureStore()
    @State private var showingSettings = false

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
