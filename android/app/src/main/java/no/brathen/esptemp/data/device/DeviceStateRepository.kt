package no.brathen.esptemp.data.device

import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import no.brathen.esptemp.domain.model.DeviceState
import java.time.Instant

/** Live alert state for one device (devices/{id}/state/current). Read-only. */
class DeviceStateRepository(private val firestore: FirebaseFirestore) {

    fun state(deviceId: String): Flow<DeviceState?> = callbackFlow {
        val registration = firestore.collection("devices").document(deviceId)
            .collection("state").document("current")
            .addSnapshotListener { snapshot, error ->
                if (error != null) return@addSnapshotListener
                if (snapshot == null || !snapshot.exists()) {
                    trySend(null)
                    return@addSnapshotListener
                }
                trySend(
                    DeviceState(
                        status = DeviceState.Status.from(snapshot.getString("status")),
                        lastReadingValue = snapshot.getDouble("lastReadingValue"),
                        lastReadingAt = (snapshot.get("lastReadingAt") as? Timestamp)?.let {
                            Instant.ofEpochSecond(it.seconds, it.nanoseconds.toLong())
                        },
                    )
                )
            }
        awaitClose { registration.remove() }
    }
}
