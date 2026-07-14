import Foundation
import Observation
import FirebaseFirestore

/// Live list of the signed-in user's devices (Firestore
/// `devices where memberUids array-contains uid`) plus threshold writes. iOS-only
/// (Sources/App). Membership is server-maintained; `uid` is enough for this query.
@Observable
@MainActor
final class DeviceStore {
    private(set) var devices: [Device] = []
    var errorMessage: String?

    private var listener: ListenerRegistration?

    func start(uid: String) {
        stop()
        listener = Firestore.firestore()
            .collection("devices")
            .whereField("memberUids", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in self?.handle(snapshot: snapshot, error: error) }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        devices = []
    }

    private func handle(snapshot: QuerySnapshot?, error: Error?) {
        if let error {
            errorMessage = error.localizedDescription
            return
        }
        guard let snapshot else { return }
        devices = snapshot.documents
            .map { doc in
                let data = doc.data()
                let t = data["thresholds"] as? [String: Any] ?? [:]
                return Device(
                    id: doc.documentID,
                    name: data["name"] as? String ?? "Sensor",
                    thresholds: DeviceThresholds(
                        minC: (t["minC"] as? NSNumber)?.doubleValue ?? DeviceThresholds.fallback.minC,
                        maxC: (t["maxC"] as? NSNumber)?.doubleValue ?? DeviceThresholds.fallback.maxC,
                        enabled: (t["enabled"] as? Bool) ?? DeviceThresholds.fallback.enabled
                    ),
                    ownerAccountId: data["ownerAccountId"] as? String
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func updateThresholds(deviceId: String, _ th: DeviceThresholds) async {
        do {
            try await Firestore.firestore()
                .collection("devices").document(deviceId)
                .setData(
                    ["thresholds": ["minC": th.minC, "maxC": th.maxC, "enabled": th.enabled]],
                    merge: true
                )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
