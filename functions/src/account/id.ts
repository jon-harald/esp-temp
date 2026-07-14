import { createHash } from "node:crypto";

/**
 * Deterministic account id derived from a verified email address.
 *
 * "Same verified email ⇒ same account" is the core identity rule, so the account
 * for an email always lives at a fixed document id. Two concurrent sign-ins for
 * the same email therefore transact on the *same* `accounts/{id}` doc, which makes
 * get-or-create race-free (a random/first-uid id would let each racer create its
 * own duplicate account). The email is trimmed + lower-cased first so casing and
 * stray whitespace never split one person into two accounts.
 */
export function accountIdForEmail(email: string): string {
  return createHash("sha256")
    .update(email.trim().toLowerCase())
    .digest("hex");
}
