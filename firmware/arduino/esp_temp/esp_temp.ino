/*
 * ESP32-S3 Feather + SHT45 -> Adafruit IO (HTTPS) with adaptive deep sleep.
 *
 * Battery-first design for a dog-in-car temperature monitor:
 *   wake -> read SHT45 + MAX17048 -> fast WiFi connect -> ONE HTTPS POST
 *   (group endpoint publishes all feeds at once) -> deep sleep.
 *
 * The sleep interval adapts to temperature (see SLEEP_*): the hotter it is,
 * the more often we wake, so measurements are dense exactly when it matters
 * and the battery lasts weeks otherwise.
 *
 * Power tricks used:
 *   - Deep sleep between cycles (~0.1 mA board-level vs ~40 mA always-on)
 *   - CPU at 80 MHz (radio does not need 240 MHz)
 *   - WiFi fast-connect: DHCP lease + AP channel/BSSID cached in RTC memory,
 *     so a wake typically reconnects in ~1s instead of ~4-6s
 *   - One HTTPS request instead of an MQTT session per cycle
 *   - NeoPixel only blinks briefly (60 ms) instead of staying lit
 *   - MAX17048 put in hibernate (it runs from VBAT and keeps SOC across sleep)
 *   - Serial wait only on cold boot (power-on/reset), never on timer wakes
 *   - WiFi.persistent(false): no NVS flash writes every cycle
 *
 * Notes:
 *   - While sleeping, USB disappears (the port re-enumerates on each wake).
 *     To watch a full cycle over serial, press RESET (cold boot waits ~1.5 s
 *     for the host) or just keep the monitor open and catch the prints.
 *   - Flashing is unchanged: hold BOOT, tap RESET, release BOOT, then esptool
 *     with --after watchdog-reset (see firmware/README.md).
 *   - RTC memory survives deep sleep but not power loss - first cycle after
 *     power-on always does a full DHCP connect and refreshes the cache.
 *
 * Board:  Adafruit Feather ESP32-S3 (4MB Flash / 2MB PSRAM, product 5477)
 * FQBN:   esp32:esp32:adafruit_feather_esp32s3
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Wire.h>
#include <Adafruit_SHT4x.h>
#include <Adafruit_MAX1704X.h>
#include <Adafruit_NeoPixel.h>
#include "esp_sleep.h"
#include "secrets.h"

// ---- Publish target: one POST creates data on every feed in the group ----
#define AIO_GROUP "default"
static const char AIO_URL[] =
    "https://io.adafruit.com/api/v2/" AIO_USERNAME "/groups/" AIO_GROUP "/data";

// ---- Adaptive sleep policy (tune freely) -------------------------------
// SLEEP_COOL_S is also the worst-case detection delay when a cool car starts
// heating up (a parked car can gain ~1 C/min), hence a fairly tight 5 min.
#define TEMP_HOT_C      30.0f
#define TEMP_WARM_C     25.0f
#define SLEEP_HOT_S      60      // >= 30 C: every minute
#define SLEEP_WARM_S    120      // 25-30 C: every 2 min
#define SLEEP_COOL_S    300      // < 25 C: every 5 min
#define SLEEP_RETRY_S    60      // after a failed cycle
#define SLEEP_BACKOFF_S 600      // after 3+ consecutive failures
#define LOW_BATT_PCT     10.0f   // below this, stretch intervals x3
#define AWAKE_BUDGET_MS 25000UL  // hard cap per wake; then sleep no matter what

// ---- State that survives deep sleep (not power loss) -------------------
typedef struct {
  bool     valid;      // WiFi cache usable?
  uint8_t  bssid[6];
  int32_t  channel;
  uint32_t ip, gw, mask, dns;
  uint16_t failCount;
  uint32_t bootCount;
} RtcState;
RTC_DATA_ATTR static RtcState rtc;

Adafruit_SHT4x sht4;
Adafruit_MAX17048 maxlipo;
Adafruit_NeoPixel pixel(1, PIN_NEOPIXEL, NEO_GRB + NEO_KHZ800);
static bool coldBoot = false;

static void blink(uint32_t color, int times) {
  for (int i = 0; i < times; i++) {
    pixel.setPixelColor(0, color);
    pixel.show();
    delay(60);
    pixel.setPixelColor(0, 0);
    pixel.show();
    if (i + 1 < times) delay(80);
  }
}

static void goToSleep(uint32_t seconds) {
  WiFi.disconnect(true);
  WiFi.mode(WIFI_OFF);
  pixel.setPixelColor(0, 0);
  pixel.show();
  digitalWrite(NEOPIXEL_POWER, LOW);   // pins power down in deep sleep anyway;
  digitalWrite(PIN_I2C_POWER, LOW);    // this covers the pre-sleep window
  Serial.printf("Sleeping %lus (boot #%lu)\n", (unsigned long)seconds, (unsigned long)rtc.bootCount);
  Serial.flush();
  esp_sleep_enable_timer_wakeup((uint64_t)seconds * 1000000ULL);
  esp_deep_sleep_start();
}

static void failSleep(const char *why) {
  Serial.printf("FAIL: %s (consecutive: %u)\n", why, rtc.failCount + 1);
  if (rtc.failCount < 1000) rtc.failCount++;
  blink(0x300000, 2);  // red double-blink
  goToSleep(rtc.failCount >= 3 ? SLEEP_BACKOFF_S : SLEEP_RETRY_S);
}

static bool waitConnected(unsigned long timeoutMs) {
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - start > timeoutMs) return false;
    if (millis() > AWAKE_BUDGET_MS) return false;
    delay(50);
  }
  return true;
}

// Fast connect using the cached lease + AP; falls back to a full DHCP join
// (and refreshes the cache) when the cache is missing or stale.
static bool connectWiFi() {
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);

  if (rtc.valid) {
    WiFi.config(IPAddress(rtc.ip), IPAddress(rtc.gw), IPAddress(rtc.mask), IPAddress(rtc.dns));
    WiFi.begin(WIFI_SSID, WIFI_PASS, rtc.channel, rtc.bssid);
    if (waitConnected(6000)) {
      Serial.printf("WiFi fast-connect OK (%lu ms)\n", millis());
      return true;
    }
    Serial.println("WiFi cache stale -> full connect");
    rtc.valid = false;
    WiFi.disconnect(true);
    WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE);  // back to DHCP
  }

  WiFi.begin(WIFI_SSID, WIFI_PASS);
  if (!waitConnected(15000)) return false;

  rtc.ip = (uint32_t)WiFi.localIP();
  rtc.gw = (uint32_t)WiFi.gatewayIP();
  rtc.mask = (uint32_t)WiFi.subnetMask();
  rtc.dns = (uint32_t)WiFi.dnsIP();
  memcpy(rtc.bssid, WiFi.BSSID(), 6);
  rtc.channel = WiFi.channel();
  rtc.valid = true;
  Serial.printf("WiFi full connect OK (%lu ms), lease cached. IP: %s\n",
                millis(), WiFi.localIP().toString().c_str());
  return true;
}

static bool publish(float tC, float rh, bool haveBatt, float vbat, float soc) {
  WiFiClientSecure net;
  net.setInsecure();  // no cert validation (key is the credential); pin a root CA to harden
  net.setTimeout(8000);

  HTTPClient http;
  http.setConnectTimeout(8000);
  http.setTimeout(8000);
  if (!http.begin(net, AIO_URL)) return false;
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-AIO-Key", AIO_KEY);
  http.addHeader("Connection", "close");

  char body[300];
  if (haveBatt) {
    snprintf(body, sizeof(body),
             "{\"feeds\":[{\"key\":\"temperature\",\"value\":\"%.2f\"},"
             "{\"key\":\"humidity\",\"value\":\"%.2f\"},"
             "{\"key\":\"esp-battery-v\",\"value\":\"%.2f\"},"
             "{\"key\":\"esp-battery-pct\",\"value\":\"%.1f\"}]}",
             tC, rh, vbat, soc);
  } else {
    snprintf(body, sizeof(body),
             "{\"feeds\":[{\"key\":\"temperature\",\"value\":\"%.2f\"},"
             "{\"key\":\"humidity\",\"value\":\"%.2f\"}]}",
             tC, rh);
  }

  int code = http.POST((uint8_t *)body, strlen(body));
  http.end();
  Serial.printf("POST -> HTTP %d (%lu ms)\n", code, millis());
  return code >= 200 && code < 300;
}

void setup() {
  coldBoot = (esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_UNDEFINED);
  setCpuFrequencyMhz(80);  // plenty for WiFi; saves ~20-30% CPU power
  rtc.bootCount++;

  Serial.begin(115200);
  if (coldBoot) {  // only stall for a serial host on power-on/reset
    unsigned long t0 = millis();
    while (!Serial && (millis() - t0 < 1500)) delay(10);
    Serial.println("\n=== esp-temp: adaptive deep-sleep build ===");
  }

  pixel.begin();
  pixel.setBrightness(20);
  pixel.setPixelColor(0, 0);
  pixel.show();

  // ---- Sensors ----
  Wire.begin();  // STEMMA QT: SDA=3, SCL=4 (GPIO7 powered by initVariant)
  if (!sht4.begin()) failSleep("SHT4x not found (check STEMMA QT cable)");
  sht4.setPrecision(SHT4X_HIGH_PRECISION);
  sht4.setHeater(SHT4X_NO_HEATER);

  sensors_event_t humidity_evt, temp_evt;
  if (!sht4.getEvent(&humidity_evt, &temp_evt)) failSleep("SHT4x read failed");
  float tC = temp_evt.temperature;
  float rh = humidity_evt.relative_humidity;

  bool haveBatt = maxlipo.begin();
  float vbat = 0, soc = 0;
  if (haveBatt) {
    vbat = maxlipo.cellVoltage();
    soc = min(maxlipo.cellPercent(), 100.0f);  // gauge reports >100% on USB/full
    maxlipo.hibernate();  // ~23 uA -> ~4 uA; it keeps tracking from VBAT
  }
  Serial.printf("Temp: %.2f C   RH: %.2f %%   Batt: %.2f V %.1f %%\n", tC, rh, vbat, soc);

  // ---- Network + publish ----
  if (!connectWiFi()) failSleep("WiFi connect timeout");
  if (millis() > AWAKE_BUDGET_MS) failSleep("awake budget exceeded");
  if (!publish(tC, rh, haveBatt, vbat, soc)) {
    rtc.valid = false;  // maybe the cached lease went bad; redo DHCP next time
    failSleep("publish failed");
  }

  // ---- Success: pick the adaptive interval and sleep ----
  rtc.failCount = 0;
  blink(0x003000, 1);  // single green blink
  uint32_t s = (tC >= TEMP_HOT_C) ? SLEEP_HOT_S
             : (tC >= TEMP_WARM_C) ? SLEEP_WARM_S
                                   : SLEEP_COOL_S;
  if (haveBatt && soc > 0 && soc < LOW_BATT_PCT) s *= 3;
  goToSleep(s);
}

void loop() {}  // never reached: setup() always ends in deep sleep
