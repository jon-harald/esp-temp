/**
 * Pure, Firebase-free alert state machine.
 *
 * Given the latest temperature, a device's thresholds and its last known alert
 * state, decide the new status and whether to send a push right now.
 *
 * Rules:
 *  - Notify on every transition INTO an alert (normal→high, normal→low, low→high, …).
 *  - While staying in the same alert, re-notify only after `cooldownMs` has passed
 *    (so a dog-in-a-hot-car keeps nagging, but not every single minute).
 *  - Notify once with an "all clear" when returning to normal from an alert.
 *  - When alerts are disabled, never notify and treat the device as normal.
 *
 * The caller is responsible for persistence: write `newStatus`, and whenever
 * `notify` is non-null set `lastNotifiedAt = now` (that is the only time it moves).
 */

export type Status = "normal" | "high" | "low";
export type NotifyKind = "high" | "low" | "clear";

export interface Thresholds {
  minC: number;
  maxC: number;
  enabled: boolean;
}

export interface AlertState {
  status: Status;
  /** Epoch millis of the last push we sent for this device, or null if none yet. */
  lastNotifiedAt: number | null;
}

export interface Decision {
  newStatus: Status;
  notify: { kind: NotifyKind } | null;
}

export function evaluate(
  valueC: number,
  th: Thresholds,
  st: AlertState,
  now: number,
  cooldownMs: number
): Decision {
  if (!th.enabled) {
    return { newStatus: "normal", notify: null };
  }

  const desired: Status =
    valueC > th.maxC ? "high" : valueC < th.minC ? "low" : "normal";

  if (desired !== "normal") {
    const isNewTransition = st.status !== desired;
    const cooledDown =
      st.lastNotifiedAt === null || now - st.lastNotifiedAt >= cooldownMs;
    const notify = isNewTransition || cooledDown ? { kind: desired } : null;
    return { newStatus: desired, notify };
  }

  // Back to normal: send a single "all clear" if we were previously alerting.
  const wasAlerting = st.status !== "normal";
  return { newStatus: "normal", notify: wasAlerting ? { kind: "clear" } : null };
}
