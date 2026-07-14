package no.brathen.esptemp.data.device

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import no.brathen.esptemp.domain.model.Device
import no.brathen.esptemp.domain.model.DeviceThresholds

/**
 * Live list of the signed-in user's devices (Firestore
 * `devices where memberUids array-contains uid`) plus threshold writes.
 * Mirrors iOS DeviceStore. Membership is server-maintained, so uid is enough.
 */
class DeviceRepository(private val firestore: FirebaseFirestore) {

    fun devices(uid: String): Flow<List<Device>> = callbackFlow {
        val registration = firestore.collection("devices")
            .whereArrayContains("memberUids", uid)
            .addSnapshotListener { snapshot, error ->
                if (error != null || snapshot == null) return@addSnapshotListener
                val devices = snapshot.documents.map { doc ->
                    val t = doc.get("thresholds") as? Map<*, *> ?: emptyMap<String, Any>()
                    Device(
                        id = doc.id,
                        name = doc.getString("name") ?: "Sensor",
                        thresholds = DeviceThresholds(
                            minC = (t["minC"] as? Number)?.toDouble() ?: DeviceThresholds.fallback.minC,
                            maxC = (t["maxC"] as? Number)?.toDouble() ?: DeviceThresholds.fallback.maxC,
                            enabled = (t["enabled"] as? Boolean) ?: DeviceThresholds.fallback.enabled,
                        ),
                        ownerAccountId = doc.getString("ownerAccountId"),
                    )
                }.sortedBy { it.name.lowercase() }
                trySend(devices)
            }
        awaitClose { registration.remove() }
    }

    suspend fun updateThresholds(deviceId: String, thresholds: DeviceThresholds) {
        firestore.collection("devices").document(deviceId)
            .set(
                mapOf(
                    "thresholds" to mapOf(
                        "minC" to thresholds.minC,
                        "maxC" to thresholds.maxC,
                        "enabled" to thresholds.enabled,
                    )
                ),
                SetOptions.merge(),
            )
            .await()
    }
}
