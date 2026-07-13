import type { DataSource } from "./types";
import { AdafruitIODataSource } from "./adafruitio";

export interface Secrets {
  adafruitIoKey: string;
  // nrfCloudKey?: string;  // future
}

/** Picks the right adapter for a device's `source` discriminator. */
export function makeDataSource(source: string, secrets: Secrets): DataSource {
  switch (source) {
    case "adafruitio":
      return new AdafruitIODataSource(secrets.adafruitIoKey);
    // case "nrfcloud":
    //   return new NrfCloudDataSource(secrets.nrfCloudKey!);   // future (nRF91)
    default:
      throw new Error(`Unknown device source: ${source}`);
  }
}

export * from "./types";
