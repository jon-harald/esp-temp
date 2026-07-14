package no.brathen.esptemp.data.push

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.tasks.await

/**
 * Owns the FCM token in Firestore under the signed-in user
 * (`users/{uid}/fcmTokens/{token}` with platform "android"). Mirrors iOS PushService.
 */
class FcmTokenRepository(
    private val auth: FirebaseAuth,
    private val firestore: FirebaseFirestore,
    private val appVersion: String,
) {
    suspend fun uploadCurrentToken() {
        val uid = auth.currentUser?.uid ?: return
        val token = FirebaseMessaging.getInstance().token.await()
        upload(uid, token)
    }

    suspend fun setToken(token: String) {
        val uid = auth.currentUser?.uid ?: return
        upload(uid, token)
    }

    private suspend fun upload(uid: String, token: String) {
        firestore.collection("users").document(uid)
            .collection("fcmTokens").document(token)
            .set(
                mapOf(
                    "platform" to "android",
                    "appVersion" to appVersion,
                    "createdAt" to FieldValue.serverTimestamp(),
                    "lastSeenAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge(),
            )
            .await()
    }

    /** MUST run while still signed in (needs the uid), i.e. before signOut. */
    suspend fun removeCurrentToken() {
        val uid = auth.currentUser?.uid
        val token = runCatching { FirebaseMessaging.getInstance().token.await() }.getOrNull()
        if (uid != null && token != null) {
            runCatching {
                firestore.collection("users").document(uid)
                    .collection("fcmTokens").document(token).delete().await()
            }
        }
        runCatching { FirebaseMessaging.getInstance().deleteToken().await() }
    }
}
