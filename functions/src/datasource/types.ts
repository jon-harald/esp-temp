/**
 * The seam that keeps the alerting logic independent of where readings come from.
 * Adafruit IO now; nRF Cloud later (ESP32 → nRF91). Only the implementation of
 * this interface changes when the data source is swapped — the poll loop and the
 * alerting logic never know the difference.
 */

export interface Reading {
  value: number;
  at: Date;
}

export interface LatestReadings {
  temperatureC: Reading | null;
  humidity?: Reading | null;
}

export interface DeviceConfig {
  source: string;
  /** Source-specific, non-secret locator (e.g. { username, feedKey }). */
  sourceConfig: Record<string, string>;
}

export interface DataSource {
  getLatestReadings(device: DeviceConfig): Promise<LatestReadings>;
}
