import SwiftUI
import FirebaseFirestore

/// Edit a device's min/max thresholds + enabled flag, and show its live server
/// status (from `devices/{id}/state/current`).
struct ThresholdsView: View {
    let device: Device
    @Environment(DeviceStore.self) private var store

    @State private var minC: Double
    @State private var maxC: Double
    @State private var enabled: Bool
    @State private var live: LiveState?
    @State private var stateListener: ListenerRegistration?
    @State private var saved = false

    init(device: Device) {
        self.device = device
        _minC = State(initialValue: device.thresholds.minC)
        _maxC = State(initialValue: device.thresholds.maxC)
        _enabled = State(initialValue: device.thresholds.enabled)
    }

    struct LiveState {
        var status: String
        var value: Double?
        var at: Date?
    }

    var body: some View {
        Form {
            Section {
                Toggle("Varsler på", isOn: $enabled)
            } footer: {
                Text("Få push når temperaturen går over maks eller under min.")
            }

            Section("Grenser") {
                Stepper(value: $maxC, in: -20...60, step: 0.5) {
                    LabeledContent("Maks (for varmt)", value: String(format: "%.1f °C", maxC))
                }
                Stepper(value: $minC, in: -40...40, step: 0.5) {
                    LabeledContent("Min (for kaldt)", value: String(format: "%.1f °C", minC))
                }
            }
            .disabled(!enabled)

            if minC >= maxC {
                Section {
                    Label("Min må være lavere enn maks.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.footnote)
                }
            }

            if let live {
                Section("Nå") {
                    LabeledContent("Status", value: statusText(live.status))
                    if let v = live.value {
                        LabeledContent("Temperatur", value: String(format: "%.1f °C", v))
                    }
                    if let at = live.at {
                        LabeledContent("Avlest", value: at.formatted(date: .omitted, time: .shortened))
                    }
                }
            }
        }
        .navigationTitle(device.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saved ? "Lagret" : "Lagre") {
                    Task {
                        await store.updateThresholds(
                            deviceId: device.id,
                            DeviceThresholds(minC: minC, maxC: maxC, enabled: enabled)
                        )
                        saved = true
                    }
                }
                .disabled(minC >= maxC)
            }
        }
        .onChange(of: minC) { _, _ in saved = false }
        .onChange(of: maxC) { _, _ in saved = false }
        .onChange(of: enabled) { _, _ in saved = false }
        .onAppear(perform: attachLiveListener)
        .onDisappear {
            stateListener?.remove()
            stateListener = nil
        }
    }

    private func attachLiveListener() {
        guard stateListener == nil else { return }
        stateListener = Firestore.firestore()
            .collection("devices").document(device.id)
            .collection("state").document("current")
            .addSnapshotListener { snapshot, _ in
                guard let data = snapshot?.data() else { return }
                live = LiveState(
                    status: data["status"] as? String ?? "normal",
                    value: (data["lastReadingValue"] as? NSNumber)?.doubleValue,
                    at: (data["lastReadingAt"] as? Timestamp)?.dateValue()
                )
            }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "high": return "For varmt 🔥"
        case "low": return "For kaldt ❄️"
        default: return "Normal ✅"
        }
    }
}
