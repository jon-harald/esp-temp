#pragma once
// Non-secret configuration. Safe to commit and to ship inside the OTA binary.
// (WiFi + Adafruit IO credentials live in NVS, not here — see provisioning.)

// Bump this on every release. The device pulls a new build whenever the OTA
// manifest's "version" differs from this string.
#define FIRMWARE_VERSION "1.1.0"

// ---- Adafruit IO ----
#define AIO_SERVER   "io.adafruit.com"
#define AIO_GROUP    "default"

// ---- Over-the-air updates (pull-based) ----
// Tiny JSON the device fetches on a schedule: {"version","url","md5"}.
// Served as a raw file from the repo's main branch.
#define OTA_MANIFEST_URL \
  "https://raw.githubusercontent.com/jon-harald/esp-temp/main/firmware/ota-manifest.json"
#define OTA_CHECK_INTERVAL_S 3600UL   // check for firmware at most once per hour
#define OTA_MAX_BOOTS        3         // unconfirmed boots before auto-rollback
#define OTA_DL_TIMEOUT_S     120       // whole download+flash must finish within this

// ---- Adaptive deep sleep (tune freely) ----
#define TEMP_HOT_C      30.0f
#define TEMP_WARM_C     25.0f
#define SLEEP_HOT_S      60      // >= 30 C: every minute
#define SLEEP_WARM_S    120      // 25-30 C: every 2 min
#define SLEEP_COOL_S    300      // < 25 C: every 5 min
#define SLEEP_RETRY_S    60      // after a failed cycle
#define SLEEP_BACKOFF_S 600      // after 3+ consecutive failures
#define LOW_BATT_PCT     10.0f   // below this, stretch intervals x3
#define AWAKE_BUDGET_MS 25000UL  // hard cap per normal wake (OTA download is exempt)
#define WDT_TIMEOUT_S    35      // watchdog: reset if a normal wake hangs this long
