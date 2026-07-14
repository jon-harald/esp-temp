import { type MulticastMessage } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { db, messaging } from "../firestore";
import { dedupeTokens, chunk, type TokenRef } from "./tokens";

export interface PushContent {
  title: string;
  body: string;
  data: Record<string, string>;
}

/** FCM's per-multicast token cap. */
const MAX_TOKENS_PER_MULTICAST = 500;

/** Builds the (token-less) message body shared by every batch. */
function buildMessage(content: PushContent): Omit<MulticastMessage, "tokens"> {
  return {
    notification: { title: content.title, body: content.body },
    data: content.data,
    apns: {
      headers: { "apns-priority": "10" },
      payload: {
        aps: {
          alert: { title: content.title, body: content.body },
          sound: "default",
          // Drives iOS Time-Sensitive delivery (breaks through most Focus modes).
          // Requires the matching entitlement in the app.
          "interruption-level": "time-sensitive",
        },
      },
    },
    android: {
      priority: "high",
      notification: { channelId: "temp-alerts" },
    },
  };
}

/**
 * Sends a Time-Sensitive push to every FCM token registered for any of `uids`,
 * then prunes tokens FCM reports as permanently dead. A device is now shared
 * across a set of member uids, so this fans out over all of them, dedupes tokens
 * (one phone can hold two logins), batches to FCM's 500-token limit, and deletes
 * each dead token from the correct owning user's subcollection.
 */
export async function sendToUids(uids: string[], content: PushContent): Promise<void> {
  const uniqueUids = [...new Set(uids)];
  if (uniqueUids.length === 0) {
    logger.warn("sendToUids called with no recipients; nothing to send");
    return;
  }

  const perUser = await Promise.all(
    uniqueUids.map(async (uid): Promise<TokenRef[]> => {
      const snap = await db.collection(`users/${uid}/fcmTokens`).get();
      return snap.docs.map((d) => ({ token: d.id, uid }));
    })
  );

  const { tokens, owner } = dedupeTokens(perUser.flat());
  if (tokens.length === 0) {
    logger.warn(`No FCM tokens for uids [${uniqueUids.join(", ")}]; nothing to send`);
    return;
  }

  const base = buildMessage(content);
  const dead: string[] = [];

  for (const batch of chunk(tokens, MAX_TOKENS_PER_MULTICAST)) {
    const resp = await messaging.sendEachForMulticast({ ...base, tokens: batch });
    resp.responses.forEach((r, i) => {
      if (r.success) return;
      const token = batch[i];
      const code = r.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-argument"
      ) {
        dead.push(token);
      } else {
        logger.error(`FCM error for token ${token}: ${code ?? "unknown"}`, r.error);
      }
    });
  }

  if (dead.length > 0) {
    await Promise.all(
      dead.map((t) => db.doc(`users/${owner.get(t)}/fcmTokens/${t}`).delete())
    );
    logger.info(`Pruned ${dead.length} dead FCM token(s)`);
  }
}

/** Back-compat wrapper: send to a single user's tokens. */
export async function sendToUser(uid: string, content: PushContent): Promise<void> {
  await sendToUids([uid], content);
}
