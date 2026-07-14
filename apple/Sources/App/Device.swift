import Foundation

/// A device the signed-in user is a member of, mirrored from Firestore `devices/{id}`.
struct Device: Identifiable, Hashable {
    let id: String
    var name: String
    var thresholds: DeviceThresholds
    /// Owning (billing) account. Owner-only actions (rename/delete/share) gate on this.
    var ownerAccountId: String?

    /// True when the given account owns this device (may manage sharing).
    func isOwner(accountId: String?) -> Bool {
        guard let accountId, let ownerAccountId else { return false }
        return accountId == ownerAccountId
    }
}

struct DeviceThresholds: Hashable {
    var minC: Double
    var maxC: Double
    var enabled: Bool

    static let fallback = DeviceThresholds(minC: 5, maxC: 30, enabled: true)
}
