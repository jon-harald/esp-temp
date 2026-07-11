import SwiftUI
import WidgetKit

struct WatchContentView: View {
    @State private var store = TemperatureStore()
    @State private var showBatteryVolts = false
    @Environment(\.scenePhase) private var scenePhase

    private var batteryText: String {
        if showBatteryVolts {
            return store.batteryVoltage.map { String(format: "%.2f V", $0.value) } ?? "–"
        }
        guard let p = store.batteryPercent?.value else { return "–" }
        return "\(Int(min(100, max(0, p.rounded())))) %"
    }

    private var batterySymbol: String {
        guard let f = store.batteryPercent.map({ min(100, max(0, $0.value)) / 100 }) else {
            return "battery.0percent"
        }
        switch f {
        case ..<0.1: return "battery.0percent"
        case ..<0.375: return "battery.25percent"
        case ..<0.625: return "battery.50percent"
        case ..<0.875: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.hasCredentials {
                    VStack(spacing: 2) {
                        Text(store.temperature.map { String(format: "%.1f°", $0.value) } ?? "–")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                        if let hum = store.humidity {
                            Text(String(format: "%.0f %% RF", hum.value))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

                    if store.batteryPercent != nil || store.batteryVoltage != nil {
                        Button {
                            withAnimation(.snappy) { showBatteryVolts.toggle() }
                        } label: {
                            HStack {
                                Label("Batteri", systemImage: batterySymbol)
                                Spacer()
                                Text(batteryText)
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
                            }
                            .font(.footnote)
                        }
                        .buttonStyle(.plain)
                    }

                    if let updated = store.temperature?.createdAt {
                        Text("Oppdatert \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Åpne appen på iPhone og legg inn Adafruit IO-innlogging.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Temp")
            .task {
                await store.refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if !Task.isCancelled { await store.refresh() }
                }
            }
            .refreshable { await store.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refresh() } }
            }
            .onChange(of: store.state) { _, newValue in
                if newValue == .loaded { WidgetCenter.shared.reloadAllTimelines() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .credentialsUpdated)) { _ in
                store.reloadCredentialFlag()
                Task { await store.refresh() }
            }
        }
    }
}

#Preview {
    WatchContentView()
}
