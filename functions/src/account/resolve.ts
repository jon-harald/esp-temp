import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../firestore";
import { accountIdForEmail } from "./id";

const REGION = "europe-west1";

/**
 * Resolves the caller's login (uid) to a canonical account, unifying every login
 * that shares one *verified* email into a single `accounts/{id}`. Called by both
 * apps at launch after sign-in.
 *
 * Verified-email is the takeover guard: an unverified email/password sign-up must
 * never be allowed to join (or seed) another person's account, so we refuse to
 * unify until `email_verified` is true. Apple and Google ID tokens already carry
 * verified emails; email/password requires the user to complete the verification
 * link first (the client sends it on sign-up).
 */
export const resolveAccount = onCall({ region: REGION }, async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Krever innlogging.");
  }

  const token = auth.token as { email?: string; email_verified?: boolean };
  const email = token.email;
  if (!email || token.email_verified !== true) {
    // No unification, no account, no access — until the email is verified.
    return { accountId: null, needsEmailVerification: true };
  }

  const uid = auth.uid;
  const emailLc = email.toLowerCase();
  const userRef = db.doc(`users/${uid}`);
  const existingAccountId = (await userRef.get()).get("accountId") as
    | string
    | undefined;

  let accountId: string;
  if (existingAccountId) {
    accountId = existingAccountId;
    // Reconcile (idempotent): make sure this email/uid is recorded on the account.
    await db
      .doc(`accounts/${accountId}`)
      .set(
        { emails: FieldValue.arrayUnion(emailLc), uids: FieldValue.arrayUnion(uid) },
        { merge: true }
      );
  } else {
    accountId = accountIdForEmail(emailLc);
    const accountRef = db.doc(`accounts/${accountId}`);
    await db.runTransaction(async (tx) => {
      const acc = await tx.get(accountRef);
      if (!acc.exists) {
        tx.set(accountRef, {
          emails: [emailLc],
          uids: [uid],
          primaryEmail: emailLc,
          createdAt: FieldValue.serverTimestamp(),
        });
      } else {
        tx.update(accountRef, {
          emails: FieldValue.arrayUnion(emailLc),
          uids: FieldValue.arrayUnion(uid),
        });
      }
      tx.set(userRef, { accountId }, { merge: true });
    });
    logger.info(`Resolved uid ${uid} -> account ${accountId}`);
  }

  // Refresh the derived cache: add this uid to memberUids of every device whose
  // authoritative memberAccountIds already grants this account access. arrayUnion
  // keeps it idempotent under concurrent launches.
  const devices = await db
    .collection("devices")
    .where("memberAccountIds", "array-contains", accountId)
    .get();
  if (!devices.empty) {
    const batch = db.batch();
    devices.docs.forEach((doc) =>
      batch.update(doc.ref, { memberUids: FieldValue.arrayUnion(uid) })
    );
    await batch.commit();
  }

  return { accountId };
});
