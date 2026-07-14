/**
 * Pure, Firebase-free helpers for the multicast send path. Kept in their own
 * module (no `firebase-admin` imports) so they can be unit-tested without
 * initializing the Admin SDK.
 */

export interface TokenRef {
  token: string;
  /** The user whose `fcmTokens` subcollection this token was read from. */
  uid: string;
}

/**
 * Dedupe FCM tokens across many users. A device shared with several accounts can
 * surface the same physical token under more than one uid (e.g. two logins on one
 * phone); sending to it twice would double-notify. First-writer-wins keeps a
 * stable owning uid per token so a later prune deletes it from the right doc.
 */
export function dedupeTokens(refs: TokenRef[]): {
  tokens: string[];
  owner: Map<string, string>;
} {
  const owner = new Map<string, string>();
  for (const { token, uid } of refs) {
    if (!owner.has(token)) owner.set(token, uid);
  }
  return { tokens: [...owner.keys()], owner };
}

/** Split into fixed-size batches (FCM multicast caps at 500 tokens per call). */
export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}
