package no.brathen.esptemp.domain.model

/** A device the signed-in user is a member of, mirrored from Firestore devices/{id}. */
data class Device(
    val id: String,
    val name: String,
    val thresholds: DeviceThresholds,
    /** Owning (billing) account; owner-only actions gate on this. */
    val ownerAccountId: String? = null,
) {
    fun isOwner(accountId: String?): Boolean =
        accountId != null && ownerAccountId != null && accountId == ownerAccountId
}

data class DeviceThresholds(
    val minC: Double,
    val maxC: Double,
    val enabled: Boolean,
) {
    companion object {
        val fallback = DeviceThresholds(minC = 5.0, maxC = 30.0, enabled = true)
    }
}
