package no.brathen.esptemp.data.auth

import com.google.firebase.functions.FirebaseFunctions
import kotlinx.coroutines.tasks.await

/**
 * Resolves the signed-in login to its canonical account via the `resolveAccount`
 * Cloud Function (europe-west1). "Same verified email ⇒ same account" is enforced
 * server-side; until the email is verified the function returns
 * needsEmailVerification and grants no account. Mirrors iOS AccountService.
 */
class AccountService(private val functions: FirebaseFunctions) {

    suspend fun resolve(): String? {
        return runCatching {
            val result = functions.getHttpsCallable("resolveAccount").call().await()
            @Suppress("UNCHECKED_CAST")
            val data = result.getData() as? Map<String, Any?>
            data?.get("accountId") as? String
        }.getOrNull()
    }
}
