import type { DataSource, DeviceConfig, LatestReadings } from "./types";

/**
 * Reads the latest value of an Adafruit IO feed via the REST API.
 * The API key comes from Secret Manager (never from the app).
 *
 * `sourceConfig.feedKey` is the feed key, optionally group-qualified
 * (e.g. "temperature" or "default.temperature").
 */
export class AdafruitIODataSource implements DataSource {
  constructor(private readonly apiKey: string) {}

  async getLatestReadings(device: DeviceConfig): Promise<LatestReadings> {
    const { username, feedKey } = device.sourceConfig;
    if (!username || !feedKey) {
      throw new Error(
        "adafruitio: sourceConfig.username and sourceConfig.feedKey are required"
      );
    }
    const url =
      `https://io.adafruit.com/api/v2/${encodeURIComponent(username)}` +
      `/feeds/${encodeURIComponent(feedKey)}`;

    const res = await fetch(url, { headers: { "X-AIO-Key": this.apiKey } });
    if (!res.ok) {
      throw new Error(`adafruitio: HTTP ${res.status} for feed ${feedKey}`);
    }
    const dto = (await res.json()) as {
      last_value?: string | null;
      updated_at?: string | null;
    };

    const value = Number(dto.last_value);
    const temperatureC =
      dto.last_value != null && Number.isFinite(value)
        ? { value, at: dto.updated_at ? new Date(dto.updated_at) : new Date() }
        : null;

    return { temperatureC };
  }
}
