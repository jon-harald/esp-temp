import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, type DocumentData } from "firebase-admin/firestore";
import { db } from "../firestore";
import { accountIdForEmail } from "../account/id";

const REGION = "europe-west1";

/**
 * Loads a device and asserts the caller owns it (or is an admin). Ownership is
 * account-level: any login of the owner account may manage sharing.
 */
async function loadOwnedDevice(
  request: CallableRequest,
  deviceId: unknown
): Promise<{ ref: FirebaseFirestore.DocumentReference; device: DocumentData }> {
  const auth = request.auth;
  if (!auth) throw new HttpsError("unauthenticated", "Krever innlogging.");
  if (typeof deviceId !== "string" || !deviceId.trim()) {
    throw new HttpsError("invalid-argument", "Mangler deviceId.");
  }

  const ref = db.doc(`devices/${deviceId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Enheten finnes ikke.");
  const device = snap.data()!;

  const isAdmin = (auth.token as { admin?: boolean }).admin === true;
  if (!isAdmin) {
    const callerAccountId = (await db.doc(`users/${auth.uid}`).get()).get(
      "accountId"
    ) as string | undefined;
    if (!callerAccountId || callerAccountId !== device.ownerAccountId) {
      throw new HttpsError("permission-denied", "Bare eieren kan dele enheten.");
    }
  }

  return { ref, device };
}

/** Validates + normalizes an email argument. */
function normalizeEmail(email: unknown): string {
  if (typeof email !== "string" || !email.trim()) {
    throw new HttpsError("invalid-argument", "Mangler e-post.");
  }
  return email.trim().toLowerCase();
}

/**
 * Resolves an email to the account that should receive access, ensuring that
 * account exists and includes the target uid. Returns the account id + its full
 * uid set (used to seed the device's derived `memberUids` cache).
 *
 * The target must have signed in at least once (so `getUserByEmail` finds them)
 * AND have a verified email — otherwise an impostor who signed up with someone
 * else's address could be granted access.
 */
async function resolveTargetAccount(
  emailLc: string
): Promise<{ accountId: string; uids: string[] }> {
  let user;
  try {
    user = await getAuth().getUserByEmail(emailLc);
  } catch {
    throw new HttpsError(
      "not-found",
      "Ingen bruker med denne e-posten. Be dem logge inn i appen først."
    );
  }

  const userAccountId = (await db.doc(`users/${user.uid}`).get()).get(
    "accountId"
  ) as string | undefined;

  // If they already resolved an account (which required a verified email), reuse it.
  if (userAccountId) {
    const uids =
      ((await db.doc(`accounts/${userAccountId}`).get()).get("uids") as
        | string[]
        | undefined) ?? [user.uid];
    return { accountId: userAccountId, uids };
  }

  // Otherwise pre-create the account for this email — but only if it's verified.
  if (!user.emailVerified) {
    throw new HttpsError(
      "failed-precondition",
      "Brukeren har ikke bekreftet e-posten sin ennå."
    );
  }

  const accountId = accountIdForEmail(emailLc);
  const accountRef = db.doc(`accounts/${accountId}`);
  await db.runTransaction(async (tx) => {
    const acc = await tx.get(accountRef);
    if (!acc.exists) {
      tx.set(accountRef, {
        emails: [emailLc],
        uids: [user.uid],
        primaryEmail: emailLc,
        createdAt: FieldValue.serverTimestamp(),
      });
    } else {
      tx.update(accountRef, {
        emails: FieldValue.arrayUnion(emailLc),
        uids: FieldValue.arrayUnion(user.uid),
      });
    }
    tx.set(db.doc(`users/${user.uid}`), { accountId }, { merge: true });
  });

  const uids =
    ((await accountRef.get()).get("uids") as string[] | undefined) ?? [user.uid];
  return { accountId, uids };
}

/**
 * Read-only lookup of the account id for an email, for revocation. Resolves the
 * same way `resolveTargetAccount` grants (existing user account, else the
 * deterministic email-derived id) but never creates anything and tolerates a
 * since-deleted user, so an owner can always undo a share.
 */
async function lookupAccountId(emailLc: string): Promise<string> {
  try {
    const user = await getAuth().getUserByEmail(emailLc);
    const userAccountId = (await db.doc(`users/${user.uid}`).get()).get(
      "accountId"
    ) as string | undefined;
    if (userAccountId) return userAccountId;
  } catch {
    // User not found / deleted — fall through to the deterministic id.
  }
  return accountIdForEmail(emailLc);
}

/**
 * Grants a device to the account owning `email`. Adds the account to the
 * authoritative `memberAccountIds` and all of its uids to the derived
 * `memberUids` cache. Idempotent.
 */
export const shareDevice = onCall({ region: REGION }, async (request) => {
  const { deviceId, email } = (request.data ?? {}) as {
    deviceId?: unknown;
    email?: unknown;
  };
  const { ref } = await loadOwnedDevice(request, deviceId);
  const emailLc = normalizeEmail(email);

  const { accountId, uids } = await resolveTargetAccount(emailLc);

  await ref.update({
    memberAccountIds: FieldValue.arrayUnion(accountId),
    memberUids: FieldValue.arrayUnion(...uids),
  });

  return { accountId };
});

/**
 * Revokes a shared account's access. The owner account can never be removed
 * (that invariant keeps `memberAccountIds`/`memberUids` non-empty).
 */
export const unshareDevice = onCall({ region: REGION }, async (request) => {
  const { deviceId, email } = (request.data ?? {}) as {
    deviceId?: unknown;
    email?: unknown;
  };
  const { ref, device } = await loadOwnedDevice(request, deviceId);
  const emailLc = normalizeEmail(email);
  const accountId = await lookupAccountId(emailLc);

  if (accountId === device.ownerAccountId) {
    throw new HttpsError("failed-precondition", "Kan ikke fjerne eieren.");
  }

  const uids =
    ((await db.doc(`accounts/${accountId}`).get()).get("uids") as
      | string[]
      | undefined) ?? [];

  const update: Record<string, unknown> = {
    memberAccountIds: FieldValue.arrayRemove(accountId),
  };
  if (uids.length > 0) {
    update.memberUids = FieldValue.arrayRemove(...uids);
  }
  await ref.update(update);

  return { accountId };
});
