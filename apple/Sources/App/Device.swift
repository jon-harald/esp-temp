import Foundation

/// A device the signed-in user owns, mirrored from Firestore `devices/{id}`.
struct Device: Identifiable, Hashable {
    let id: String
    var name: String
    var thresholds: DeviceThresholds
}

struct DeviceThresholds: Hashable {
    var minC: Double
    var maxC: Double
    var enabled: Bool

    static let fallback = DeviceThresholds(minC: 5, maxC: 30, enabled: true)
}
