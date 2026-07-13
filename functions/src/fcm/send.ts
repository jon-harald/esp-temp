import { type MulticastMessage } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { db, messaging } from "../firestore";

export interface PushContent {
  title: string;
  body: string;
  data: Record<string, string>;
}

/**
 * Sends a Time-Sensitive push to every FCM token registered for `uid`,
 * then prunes tokens FCM reports as permanently dead.
 */
export async function sendToUser(uid: string, content: PushContent): Promise<void> {
  const tokensSnap = await db.collection(`users/${uid}/fcmTokens`).get();
  const tokens = tokensSnap.docs.map((d) => d.id);
  if (tokens.length === 0) {
    logger.warn(`No FCM tokens for user ${uid}; nothing to send`);
    return;
  }

  const message: MulticastMessage = {
    tokens,
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

  const resp = await messaging.sendEachForMulticast(message);

  const dead: string[] = [];
  resp.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error?.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-argument"
    ) {
      dead.push(tokens[i]);
    } else {
      logger.error(`FCM error for token ${tokens[i]}: ${code ?? "unknown"}`, r.error);
    }
  });

  if (dead.length > 0) {
    await Promise.all(dead.map((t) => db.doc(`users/${uid}/fcmTokens/${t}`).delete()));
    logger.info(`Pruned ${dead.length} dead FCM token(s) for user ${uid}`);
  }
}
