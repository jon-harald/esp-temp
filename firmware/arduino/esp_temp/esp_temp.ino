/*
 * ESP32-S3 Feather + SHT45 -> Adafruit IO, with adaptive deep sleep and
 * robust pull-based OTA. Dog-in-car temperature monitor.
 *
 * Each wake: read SHT45 + MAX17048 -> fast WiFi connect -> one HTTPS POST ->
 * (hourly) check for new firmware -> deep sleep.
 *
 * Credentials (WiFi + Adafruit IO) live in NVS, NOT in this binary, so the
 * compiled .bin is safe to host publicly for OTA. Provision once over serial:
 *   PROV {"ssid":"..","pass":"..","user":"..","key":".."}
 *
 * OTA is pull-based and failure-tolerant:
 *   - fetch a tiny manifest {version,url,md5}; download only if version differs
 *   - Update writes the inactive partition; a partial/corrupt image is rejected
 *     and the running firmware is untouched (a half-flash is impossible)
 *   - the .bin's MD5 (from the manifest) and the image's built-in SHA are checked
 *   - after applying, the NEW firmware must prove itself healthy (one good
 *     publish) within OTA_MAX_BOOTS boots, else it auto-rolls back to the
 *     previous firmware. Survives power loss (state in NVS) and boot-loops.
 *   - a version that rolled back is remembered and skipped until a new one ships
 *   - a watchdog resets the board if a wake ever hangs
 *   - OTA never blocks monitoring: any failure just continues normal operation
 *
 * Board:  Adafruit Feather ESP32-S3 (4MB Flash / 2MB PSRAM, product 5477)
 * FQBN:   esp32:esp32:adafruit_feather_esp32s3
 * Partition scheme: min_spiffs (OTA-capable). See firmware/README.md for flashing.
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Wire.h>
#include <Adafruit_SHT4x.h>
#include <Adafruit_MAX1704X.h>
#include <Adafruit_NeoPixel.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <Update.h>
#include "esp_sleep.h"
#include "esp_task_wdt.h"
#include "esp_ota_ops.h"
#include "config.h"

// ---- State that survives deep sleep (not power loss). Garbage on cold boot. ----
typedef struct {
  bool     wifiValid;
  uint8_t  bssid[6];
  int32_t  channel;
  uint32_t ip, gw, mask, dns;
  uint16_t failCount;
  uint32_t bootCount;
  uint32_t secsSinceOtaCheck;
} RtcState;
RTC_DATA_ATTR static RtcState rtc;

Preferences prefs;  // NVS namespace "esptemp": creds + OTA bookkeeping (survives power loss)
String wifiSsid, wifiPass, aioUser, aioKey;

Adafruit_SHT4x sht4;
Adafruit_MAX17048 maxlipo;
Adafruit_NeoPixel pixel(1, PIN_NEOPIXEL, NEO_GRB + NEO_KHZ800);
static bool coldBoot = false;

static const uint32_t C_BLUE = 0x000030, C_GREEN = 0x003000, C_RED = 0x300000;

static void blink(uint32_t color, int times) {
  for (int i = 0; i < times; i++) {
    pixel.setPixelColor(0, color); pixel.show(); delay(60);
    pixel.setPixelColor(0, 0);     pixel.show();
    if (i + 1 < times) delay(80);
  }
}

static void feedWdt() { esp_task_wdt_reset(); }

static void goToSleep(uint32_t seconds) {
  rtc.secsSinceOtaCheck += seconds;
  WiFi.disconnect(true);
  WiFi.mode(WIFI_OFF);
  pixel.setPixelColor(0, 0); pixel.show();
  Serial.printf("Sleeping %lus (boot #%lu, sinceOtaChk %lus)\n",
                (unsigned long)seconds, (unsigned long)rtc.bootCount,
                (unsigned long)rtc.secsSinceOtaCheck);
  Serial.flush();
  esp_sleep_enable_timer_wakeup((uint64_t)seconds * 1000000ULL);
  esp_deep_sleep_start();
}

static void failSleep(const char *why) {
  Serial.printf("FAIL: %s (consecutive: %u)\n", why, rtc.failCount + 1);
  if (rtc.failCount < 1000) rtc.failCount++;
  blink(C_RED, 2);
  goToSleep(rtc.failCount >= 3 ? SLEEP_BACKOFF_S : SLEEP_RETRY_S);
}

// ===================== Credentials (NVS) + provisioning =====================
static bool loadCreds() {
  prefs.begin("esptemp", true);
  wifiSsid = prefs.getString("wifi_ssid", "");
  wifiPass = prefs.getString("wifi_pass", "");
  aioUser  = prefs.getString("aio_user", "");
  aioKey   = prefs.getString("aio_key", "");
  prefs.end();
  return wifiSsid.length() && aioUser.length() && aioKey.length();
}

// No creds in NVS -> wait (awake, no sleep) for a provisioning line over serial.
static void provisioningMode() {
  Serial.println("\n*** PROVISIONING NEEDED ***");
  Serial.println("Send one line:  PROV {\"ssid\":\"..\",\"pass\":\"..\",\"user\":\"..\",\"key\":\"..\"}");
  String line;
  while (true) {
    blink(C_BLUE, 1); delay(700);
    if (!Serial.available()) continue;
    line = Serial.readStringUntil('\n'); line.trim();
    if (!line.startsWith("PROV ")) continue;
    JsonDocument doc;
    if (deserializeJson(doc, line.substring(5))) { Serial.println("PROV ERROR: bad JSON"); continue; }
    prefs.begin("esptemp", false);
    prefs.putString("wifi_ssid", (const char *)(doc["ssid"] | ""));
    prefs.putString("wifi_pass", (const char *)(doc["pass"] | ""));
    prefs.putString("aio_user",  (const char *)(doc["user"] | ""));
    prefs.putString("aio_key",   (const char *)(doc["key"]  | ""));
    prefs.end();
    Serial.println("PROV OK -> saved to NVS, rebooting");
    delay(300);
    ESP.restart();
  }
}

// ===================== WiFi (cached fast-connect) =====================
static bool waitConnected(unsigned long timeoutMs) {
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - start > timeoutMs) return false;
    feedWdt();
    delay(50);
  }
  return true;
}

static bool connectWiFi() {
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  if (rtc.wifiValid) {
    WiFi.config(IPAddress(rtc.ip), IPAddress(rtc.gw), IPAddress(rtc.mask), IPAddress(rtc.dns));
    WiFi.begin(wifiSsid.c_str(), wifiPass.c_str(), rtc.channel, rtc.bssid);
    if (waitConnected(6000)) { Serial.printf("WiFi fast-connect OK (%lu ms)\n", millis()); return true; }
    rtc.wifiValid = false;
    WiFi.disconnect(true);
    WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE);
  }
  WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
  if (!waitConnected(15000)) return false;
  rtc.ip = (uint32_t)WiFi.localIP();  rtc.gw = (uint32_t)WiFi.gatewayIP();
  rtc.mask = (uint32_t)WiFi.subnetMask(); rtc.dns = (uint32_t)WiFi.dnsIP();
  memcpy(rtc.bssid, WiFi.BSSID(), 6); rtc.channel = WiFi.channel(); rtc.wifiValid = true;
  Serial.printf("WiFi full connect OK (%lu ms). IP: %s\n", millis(), WiFi.localIP().toString().c_str());
  return true;
}

// ===================== Publish (one HTTPS POST -> all feeds) =====================
static bool publish(float tC, float rh, bool haveBatt, float vbat, float soc) {
  WiFiClientSecure net; net.setInsecure(); net.setTimeout(8000);
  HTTPClient http; http.setConnectTimeout(8000); http.setTimeout(8000);
  String url = String("https://") + AIO_SERVER + "/api/v2/" + aioUser + "/groups/" + AIO_GROUP + "/data";
  if (!http.begin(net, url)) return false;
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-AIO-Key", aioKey);
  http.addHeader("Connection", "close");

  char body[384];
  int n = snprintf(body, sizeof(body),
      "{\"feeds\":[{\"key\":\"temperature\",\"value\":\"%.2f\"},{\"key\":\"humidity\",\"value\":\"%.2f\"}",
      tC, rh);
  if (haveBatt)
    n += snprintf(body + n, sizeof(body) - n,
      ",{\"key\":\"esp-battery-v\",\"value\":\"%.2f\"},{\"key\":\"esp-battery-pct\",\"value\":\"%.1f\"}",
      vbat, soc);
  if (coldBoot)  // report firmware version on power-on / after an OTA reboot
    n += snprintf(body + n, sizeof(body) - n,
      ",{\"key\":\"esp-fw\",\"value\":\"%s\"}", FIRMWARE_VERSION);
  snprintf(body + n, sizeof(body) - n, "]}");

  int code = http.POST((uint8_t *)body, strlen(body));
  http.end();
  Serial.printf("POST -> HTTP %d (%lu ms)\n", code, millis());
  return code >= 200 && code < 300;
}

// ===================== OTA (pull) =====================
static bool fetchManifest(String &ver, String &url, String &md5) {
  WiFiClientSecure c; c.setInsecure(); c.setTimeout(10000);
  HTTPClient http; http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS); http.setTimeout(10000);
  if (!http.begin(c, OTA_MANIFEST_URL)) return false;
  int code = http.GET();
  if (code != HTTP_CODE_OK) { Serial.printf("OTA manifest HTTP %d\n", code); http.end(); return false; }
  String payload = http.getString();
  http.end();
  JsonDocument doc;
  if (deserializeJson(doc, payload)) return false;
  ver = (const char *)(doc["version"] | "");
  url = (const char *)(doc["url"] | "");
  md5 = (const char *)(doc["md5"] | "");
  return ver.length() && url.length();
}

static bool downloadAndApply(const String &url, const String &md5) {
  WiFiClientSecure c; c.setInsecure(); c.setTimeout(15000);
  HTTPClient http; http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS); http.setTimeout(15000);
  if (!http.begin(c, url)) return false;
  int code = http.GET();
  if (code != HTTP_CODE_OK) { Serial.printf("OTA GET HTTP %d\n", code); http.end(); return false; }
  int len = http.getSize();
  if (len <= 0) { Serial.println("OTA: unknown content length"); http.end(); return false; }

  if (!Update.begin(len)) { Serial.printf("Update.begin: %s\n", Update.errorString()); http.end(); return false; }
  if (md5.length() == 32) Update.setMD5(md5.c_str());  // verified in Update.end()

  WiFiClient *stream = http.getStreamPtr();
  uint8_t buf[1460];
  int written = 0;
  unsigned long start = millis();
  while (written < len) {
    if (millis() - start > OTA_DL_TIMEOUT_S * 1000UL) { Serial.println("OTA: download timeout"); Update.abort(); http.end(); return false; }
    if (!http.connected() && stream->available() == 0) { Serial.println("OTA: connection dropped"); Update.abort(); http.end(); return false; }
    int avail = stream->available();
    if (avail <= 0) { feedWdt(); delay(2); continue; }
    int n = stream->readBytes(buf, min(avail, (int)sizeof(buf)));
    if (Update.write(buf, n) != (size_t)n) { Serial.printf("Update.write: %s\n", Update.errorString()); Update.abort(); http.end(); return false; }
    written += n;
    feedWdt();
    if (written % 65536 < 1460) Serial.printf("OTA: %d/%d\n", written, len);
  }
  http.end();
  if (!Update.end(true)) { Serial.printf("Update.end: %s\n", Update.errorString()); return false; }  // checks MD5 + image SHA
  return Update.isFinished();
}

static void maybeCheckOta() {
  String ver, url, md5;
  if (!fetchManifest(ver, url, md5)) { Serial.println("OTA: manifest unavailable"); return; }
  Serial.printf("OTA: running %s, manifest %s\n", FIRMWARE_VERSION, ver.c_str());
  if (ver == FIRMWARE_VERSION) return;

  prefs.begin("esptemp", true);
  String bad = prefs.getString("ota_bad_ver", "");
  prefs.end();
  if (ver == bad) { Serial.printf("OTA: skipping known-bad %s\n", ver.c_str()); return; }

  Serial.printf("OTA: downloading %s ...\n", ver.c_str());
  blink(C_BLUE, 3);
  if (downloadAndApply(url, md5)) {
    prefs.begin("esptemp", false);
    prefs.putBool("ota_pending", true);
    prefs.putUChar("ota_boots", 0);
    prefs.putString("ota_target", ver);
    prefs.end();
    Serial.println("OTA: applied -> rebooting into new firmware");
    delay(200);
    ESP.restart();
  }
  Serial.println("OTA: failed, staying on current firmware");
}

// Called very early: increment the unconfirmed-boot counter, roll back if a
// freshly-applied firmware never proved itself healthy.
static void rollbackGuard() {
  prefs.begin("esptemp", false);
  if (prefs.getBool("ota_pending", false)) {
    uint8_t boots = prefs.getUChar("ota_boots", 0) + 1;
    prefs.putUChar("ota_boots", boots);
    Serial.printf("OTA: unconfirmed boot %u/%u\n", boots, OTA_MAX_BOOTS);
    if (boots > OTA_MAX_BOOTS) {
      String bad = prefs.getString("ota_target", "");
      prefs.putString("ota_bad_ver", bad);
      prefs.putBool("ota_pending", false);
      prefs.putUChar("ota_boots", 0);
      prefs.end();
      Serial.printf("OTA: rolling back bad firmware %s\n", bad.c_str());
      if (Update.canRollBack() && Update.rollBack()) { delay(200); ESP.restart(); }
      Serial.println("OTA: rollback unavailable (continuing)");
      return;
    }
  }
  prefs.end();
}

static void confirmHealthy() {
  prefs.begin("esptemp", false);
  if (prefs.getBool("ota_pending", false)) {
    prefs.putBool("ota_pending", false);
    prefs.putUChar("ota_boots", 0);
    prefs.remove("ota_bad_ver");
    prefs.end();
    esp_ota_mark_app_valid_cancel_rollback();
    Serial.println("OTA: confirmed healthy.");
  } else {
    prefs.end();
  }
}

// ===================== main =====================
void setup() {
  coldBoot = (esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_UNDEFINED);
  if (coldBoot) memset(&rtc, 0, sizeof(rtc));
  setCpuFrequencyMhz(80);
  rtc.bootCount++;

  Serial.begin(115200);
  if (coldBoot) { unsigned long t0 = millis(); while (!Serial && millis() - t0 < 1500) delay(10);
    Serial.printf("\n=== esp-temp %s (adaptive sleep + OTA) ===\n", FIRMWARE_VERSION); }

  rollbackGuard();  // may reboot into the previous firmware

  if (!loadCreds()) provisioningMode();  // never returns without creds

  esp_task_wdt_config_t wdt = { .timeout_ms = WDT_TIMEOUT_S * 1000, .idle_core_mask = 0, .trigger_panic = true };
  esp_task_wdt_reconfigure(&wdt);
  esp_task_wdt_add(NULL);

  pixel.begin(); pixel.setBrightness(20); pixel.setPixelColor(0, 0); pixel.show();

  Wire.begin();  // STEMMA QT: SDA=3, SCL=4 (GPIO7 powered by initVariant)
  bool haveBatt = maxlipo.begin();       // reset now; first ADC ~250 ms later
  unsigned long battStarted = millis();

  if (!sht4.begin()) failSleep("SHT4x not found (check STEMMA QT cable)");
  sht4.setPrecision(SHT4X_HIGH_PRECISION);
  sht4.setHeater(SHT4X_NO_HEATER);
  sensors_event_t hum_evt, temp_evt;
  if (!sht4.getEvent(&hum_evt, &temp_evt)) failSleep("SHT4x read failed");
  float tC = temp_evt.temperature, rh = hum_evt.relative_humidity;
  Serial.printf("Temp: %.2f C   RH: %.2f %%\n", tC, rh);

  if (!connectWiFi()) failSleep("WiFi connect timeout");

  float vbat = 0, soc = 0;
  if (haveBatt) {
    while (millis() - battStarted < 400) delay(10);
    vbat = maxlipo.cellVoltage();
    soc = min(maxlipo.cellPercent(), 100.0f);
    maxlipo.hibernate();
    if (vbat < 0.5f) haveBatt = false;
    Serial.printf("Batt: %.2f V  %.1f %%\n", vbat, soc);
  }

  if (millis() > AWAKE_BUDGET_MS) failSleep("awake budget exceeded before publish");
  if (!publish(tC, rh, haveBatt, vbat, soc)) { rtc.wifiValid = false; failSleep("publish failed"); }

  rtc.failCount = 0;
  confirmHealthy();  // a good publish proves a freshly-applied OTA is healthy

  if (coldBoot || rtc.secsSinceOtaCheck >= OTA_CHECK_INTERVAL_S) {
    maybeCheckOta();          // may reboot into new firmware; download is WDT-fed + time-capped
    rtc.secsSinceOtaCheck = 0;
  }

  blink(C_GREEN, 1);
  uint32_t s = (tC >= TEMP_HOT_C) ? SLEEP_HOT_S : (tC >= TEMP_WARM_C) ? SLEEP_WARM_S : SLEEP_COOL_S;
  if (haveBatt && soc > 0 && soc < LOW_BATT_PCT) s *= 3;
  goToSleep(s);
}

void loop() {}  // never reached: setup() always ends in deep sleep
