import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { FieldValue, type DocumentData } from "firebase-admin/firestore";
import { db } from "./firestore";
import { makeDataSource, type Secrets } from "./datasource";
import {
  evaluate,
  type AlertState,
  type NotifyKind,
  type Status,
  type Thresholds,
} from "./alerting/evaluate";
import { sendToUser, type PushContent } from "./fcm/send";

const ADAFRUIT_IO_KEY = defineSecret("ADAFRUIT_IO_KEY");

/** Re-notify at most this often while a device stays in the same alert state. */
const COOLDOWN_MS = 15 * 60 * 1000;
/** Cap concurrent data-source fetches so a growing fleet stays within the timeout. */
const MAX_CONCURRENCY = 8;

/**
 * Checks every device once a minute. Flat cost as the fleet grows: one function
 * run reads all devices and hits the data source once per device.
 */
export const pollDevices = onSchedule(
  {
    schedule: "every 1 minutes",
    region: "europe-west1",
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: [ADAFRUIT_IO_KEY],
  },
  async () => {
    await runPoll({ adafruitIoKey: ADAFRUIT_IO_KEY.value() }, Date.now());
  }
);

/**
 * The poll body, exported as a plain async function so the emulator,
 * `firebase functions:shell`, and tests can drive it directly (the Functions
 * emulator does not run schedules automatically).
 */
export async function runPoll(secrets: Secrets, now: number): Promise<void> {
  const devicesSnap = await db.collection("devices").get();
  logger.info(`Polling ${devicesSnap.size} device(s)`);

  await mapWithConcurrency(devicesSnap.docs, MAX_CONCURRENCY, async (doc) => {
    try {
      await pollOneDevice(doc.id, doc.data(), secrets, now);
    } catch (err) {
      logger.error(`Device ${doc.id} poll failed`, err as Error);
    }
  });
}

async function pollOneDevice(
  deviceId: string,
  device: DocumentData,
  secrets: Secrets,
  now: number
): Promise<void> {
  const ownerUid: string | undefined = device.ownerUid;
  const thresholds = device.thresholds as Thresholds | undefined;
  if (!ownerUid || !thresholds) {
    logger.warn(`Device ${deviceId} missing ownerUid/thresholds; skipping`);
    return;
  }

  const dataSource = makeDataSource(device.source, secrets);
  const readings = await dataSource.getLatestReadings({
    source: device.source,
    sourceConfig: device.sourceConfig ?? {},
  });
  const temp = readings.temperatureC;
  if (!temp) {
    logger.warn(`Device ${deviceId} has no temperature reading; skipping`);
    return;
  }

  const stateRef = db.doc(`devices/${deviceId}/state/current`);
  const prev = (await stateRef.get()).data() as
    | { status?: Status; lastNotifiedAt?: number }
    | undefined;
  const state: AlertState = {
    status: prev?.status ?? "normal",
    lastNotifiedAt: prev?.lastNotifiedAt ?? null,
  };

  const decision = evaluate(temp.value, thresholds, state, now, COOLDOWN_MS);

  const update: Record<string, unknown> = {
    status: decision.newStatus,
    lastReadingValue: temp.value,
    lastReadingAt: temp.at,
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (decision.notify) {
    update.lastNotifiedAt = now;
    await sendToUser(
      ownerUid,
      buildContent(device.name ?? "Sensor", decision.notify.kind, temp.value, thresholds, deviceId)
    );
    logger.info(`Device ${deviceId}: notified ${decision.notify.kind} @ ${temp.value}°C`);
  }

  await stateRef.set(update, { merge: true });
}

function buildContent(
  name: string,
  kind: NotifyKind,
  value: number,
  th: Thresholds,
  deviceId: string
): PushContent {
  const v = value.toFixed(1);
  let title: string;
  let body: string;
  switch (kind) {
    case "high":
      title = `🔥 ${name}: for varmt`;
      body = `${v}°C – over grensen på ${th.maxC}°C`;
      break;
    case "low":
      title = `❄️ ${name}: for kaldt`;
      body = `${v}°C – under grensen på ${th.minC}°C`;
      break;
    case "clear":
      title = `✅ ${name}: normal igjen`;
      body = `${v}°C – innenfor grensene`;
      break;
  }
  return { title, body, data: { deviceId, kind, value: v } };
}

async function mapWithConcurrency<T>(
  items: T[],
  limit: number,
  fn: (item: T) => Promise<void>
): Promise<void> {
  let cursor = 0;
  const workerCount = Math.min(limit, items.length);
  const workers = Array.from({ length: workerCount }, async () => {
    while (cursor < items.length) {
      const index = cursor++;
      await fn(items[index]);
    }
  });
  await Promise.all(workers);
}
