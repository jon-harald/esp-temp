/**
 * One-time migration + bootstrap for the account-identity / membership model.
 *
 * Full migration (no args): for every device, resolve its legacy `ownerUid` to a
 * verified-email account, backfill `users/{uid}.accountId`, and set the device's
 * `ownerAccountId`, `memberAccountIds` and derived `memberUids`. Idempotent.
 *
 * Bootstrap (grant a login access without waiting for auto-unify by email):
 *   node functions/scripts/migrate-memberUids.mjs --device <id> --add-email <E>
 *   node functions/scripts/migrate-memberUids.mjs --device <id> --add-uid <U>
 *
 * Credentials:
 *   Prod:     GOOGLE_APPLICATION_CREDENTIALS=./sa.json GCLOUD_PROJECT=temptracker-54c75 node ...
 *   Emulator: FIRESTORE_EMULATOR_HOST=localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *             GCLOUD_PROJECT=temptracker-54c75 node ...
 *
 * RUN ORDER: migrate FIRST, then deploy firestore.rules, then deploy functions.
 * Deploying the rules before migrating makes every legacy device unreadable
 * (the rules require `memberUids`, and owner checks require `users.accountId`).
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { createHash } from "node:crypto";

const projectId =
  process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || undefined;
initializeApp(projectId ? { projectId } : undefined);

const db = getFirestore();
const auth = getAuth();

/** Must match functions/src/account/id.ts::accountIdForEmail. */
function accountIdForEmail(email) {
  return createHash("sha256").update(email.trim().toLowerCase()).digest("hex");
}

/**
 * Ensures an account exists for a uid (keyed by its verified email, or a uid
 * fallback if the email is missing/unverified), records the uid + email on it,
 * and points users/{uid}.accountId at it. Returns the account id.
 */
async function ensureAccountForUid(uid) {
  const user = await auth.getUser(uid); // throws if the uid no longer exists
  const email = user.email;
  const emailLc = email ? email.toLowerCase() : null;

  let accountId;
  if (emailLc && user.emailVerified) {
    accountId = accountIdForEmail(emailLc);
  } else {
    accountId = `uid_${uid}`;
    console.warn(
      `  ! uid ${uid} has ${email ? "unverified" : "no"} email; using fallback account ${accountId}`
    );
  }

  const accountRef = db.doc(`accounts/${accountId}`);
  const snap = await accountRef.get();
  if (!snap.exists) {
    await accountRef.set({
      emails: emailLc ? [emailLc] : [],
      uids: [uid],
      primaryEmail: emailLc,
      createdAt: FieldValue.serverTimestamp(),
    });
  } else {
    await accountRef.update({
      ...(emailLc ? { emails: FieldValue.arrayUnion(emailLc) } : {}),
      uids: FieldValue.arrayUnion(uid),
    });
  }
  await db.doc(`users/${uid}`).set({ accountId }, { merge: true });
  return accountId;
}

/** Adds an account (and all its uids) to a device's membership + derived cache. */
async function addAccountToDevice(deviceRef, accountId, { setOwner = false } = {}) {
  const accUids =
    (await db.doc(`accounts/${accountId}`).get()).get("uids") ?? [];
  const update = { memberAccountIds: FieldValue.arrayUnion(accountId) };
  if (accUids.length > 0) update.memberUids = FieldValue.arrayUnion(...accUids);
  if (setOwner) update.ownerAccountId = accountId;
  await deviceRef.update(update);
}

async function runFullMigration() {
  const devices = await db.collection("devices").get();
  console.log(`Migrating ${devices.size} device(s)…`);

  const ownerUids = [
    ...new Set(devices.docs.map((d) => d.get("ownerUid")).filter(Boolean)),
  ];
  const accountByUid = {};
  for (const uid of ownerUids) {
    try {
      accountByUid[uid] = await ensureAccountForUid(uid);
      console.log(`✓ account ${accountByUid[uid]} for owner ${uid}`);
    } catch (e) {
      console.warn(`! could not resolve owner ${uid}: ${e.message}`);
    }
  }

  let migrated = 0;
  let skipped = 0;
  for (const doc of devices.docs) {
    const ownerUid = doc.get("ownerUid");
    if (!ownerUid) {
      console.warn(`! device ${doc.id}: no ownerUid; skipping`);
      skipped++;
      continue;
    }
    const accountId = accountByUid[ownerUid];
    if (!accountId) {
      console.warn(`! device ${doc.id}: no account for owner ${ownerUid}; skipping`);
      skipped++;
      continue;
    }
    await addAccountToDevice(doc.ref, accountId, { setOwner: true });
    console.log(`✓ device ${doc.id}: ownerAccountId=${accountId}`);
    migrated++;
  }
  console.log(`Done. migrated=${migrated} skipped=${skipped}`);
}

async function runBootstrap(deviceId, { addEmail, addUid }) {
  const ref = db.doc(`devices/${deviceId}`);
  if (!(await ref.get()).exists) throw new Error(`device ${deviceId} not found`);

  let accountId;
  if (addEmail) {
    const user = await auth.getUserByEmail(addEmail.toLowerCase());
    accountId = await ensureAccountForUid(user.uid);
  } else {
    accountId = await ensureAccountForUid(addUid);
  }
  await addAccountToDevice(ref, accountId);
  console.log(`✓ shared device ${deviceId} with account ${accountId}`);
}

function getFlag(args, name) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}

async function main() {
  const args = process.argv.slice(2);
  const deviceId = getFlag(args, "--device");
  const addEmail = getFlag(args, "--add-email");
  const addUid = getFlag(args, "--add-uid");

  if (deviceId) {
    if (!addEmail && !addUid) {
      throw new Error("--device requires --add-email <E> or --add-uid <U>");
    }
    await runBootstrap(deviceId, { addEmail, addUid });
  } else {
    await runFullMigration();
  }
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error(err);
    process.exit(1);
  }
);
