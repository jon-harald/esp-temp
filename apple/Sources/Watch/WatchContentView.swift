import SwiftUI
import WidgetKit

struct WatchContentView: View {
    @State private var store = TemperatureStore()

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
            .task { await store.refresh() }
            .refreshable { await store.refresh() }
            .onChange(of: store.state) { _, newValue in
                if newValue == .loaded { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
    }
}

#Preview {
    WatchContentView()
}
