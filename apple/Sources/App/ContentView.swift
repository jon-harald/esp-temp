import SwiftUI
import Charts
import WidgetKit

struct ContentView: View {
    @State private var store = TemperatureStore()
    @State private var devices = DeviceStore()
    @State private var showingSettings = false
    @State private var showingAccount = false
    @State private var showBatteryVolts = false
    @State private var path = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthManager.self) private var auth

    private let refreshInterval: Duration = .seconds(30)

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !store.hasCredentials {
                    needsSetup
                } else {
                    content
                }
            }
            .environment(devices)
            .navigationTitle("Temperatur")
            .navigationDestination(for: Device.self) { device in
                ThresholdsView(device: device)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingAccount = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
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
            .sheet(isPresented: $showingAccount) {
                AccountView().environment(auth)
            }
            .task {
                if let uid = auth.user?.uid { devices.start(uid: uid) }
                await store.refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: refreshInterval)
                    if !Task.isCancelled { await store.refresh() }
                }
            }
            .refreshable { await store.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refresh() } }
            }
            .onChange(of: PushService.shared.pendingDeepLinkDeviceId) { _, id in
                guard let id, let device = devices.devices.first(where: { $0.id == id }) else { return }
                path.append(device)
                PushService.shared.pendingDeepLinkDeviceId = nil
            }
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

            Section("Varsling") {
                if devices.devices.isEmpty {
                    Text("Ingen enheter registrert på kontoen din ennå.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(devices.devices) { device in
                        NavigationLink(value: device) { thresholdRow(device) }
                    }
                }
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

    private func thresholdRow(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(device.name)
            if device.thresholds.enabled {
                Text(String(format: "Varsler under %.0f° / over %.0f°",
                            device.thresholds.minC, device.thresholds.maxC))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Varsler av")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .environment(AuthManager())
}
