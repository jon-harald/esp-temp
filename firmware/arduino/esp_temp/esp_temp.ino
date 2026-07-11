/*
 * ESP32-S3 Feather + SHT45 (STEMMA QT / I2C) -> Adafruit IO (MQTT/TLS)
 *
 * Reads temperature + humidity from an Adafruit SHT45 (product 5665) on the
 * STEMMA QT connector and publishes to Adafruit IO every PUBLISH_INTERVAL_MS.
 * View live on iPhone via the Adafruit IO dashboard in Safari (no app needed).
 *
 * Board:  Adafruit Feather ESP32-S3 (4MB Flash / 2MB PSRAM, product 5477)
 * FQBN:   esp32:esp32:adafruit_feather_esp32s3
 * Serial: 115200 baud over USB (USB CDC On Boot = Enabled)
 *
 * The board core's initVariant() already powers the STEMMA QT / I2C port
 * (GPIO7) and the NeoPixel (GPIO21) HIGH before setup(), so no extra power
 * handling is needed here.
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Wire.h>
#include <Adafruit_SHT4x.h>
#include <Adafruit_MAX1704X.h>
#include <Adafruit_MQTT.h>
#include <Adafruit_MQTT_Client.h>
#include <Adafruit_NeoPixel.h>
#include "secrets.h"

// ---- Adafruit IO connection ----
#define AIO_SERVER      "io.adafruit.com"
#define AIO_SERVERPORT  8883                 // MQTT over TLS
#define PUBLISH_INTERVAL_MS 30000UL          // publish every 30 s

WiFiClientSecure net;
Adafruit_MQTT_Client mqtt(&net, AIO_SERVER, AIO_SERVERPORT, AIO_USERNAME, AIO_KEY);

// Feed topics: <username>/feeds/<feed-key>  (feeds auto-create on first publish)
Adafruit_MQTT_Publish tempFeed = Adafruit_MQTT_Publish(&mqtt, AIO_USERNAME "/feeds/temperature");
Adafruit_MQTT_Publish humFeed  = Adafruit_MQTT_Publish(&mqtt, AIO_USERNAME "/feeds/humidity");
Adafruit_MQTT_Publish battVFeed   = Adafruit_MQTT_Publish(&mqtt, AIO_USERNAME "/feeds/esp-battery-v");
Adafruit_MQTT_Publish battPctFeed = Adafruit_MQTT_Publish(&mqtt, AIO_USERNAME "/feeds/esp-battery-pct");

Adafruit_SHT4x sht4;
Adafruit_MAX17048 maxlipo;   // onboard LiPo fuel gauge (I2C 0x36)
bool haveBattery = false;
Adafruit_NeoPixel pixel(1, PIN_NEOPIXEL, NEO_GRB + NEO_KHZ800);

static const uint32_t C_BLUE   = 0x000030;
static const uint32_t C_YELLOW = 0x302000;
static const uint32_t C_GREEN  = 0x003000;
static const uint32_t C_RED    = 0x300000;

void setPixel(uint32_t color) {
  pixel.setPixelColor(0, color);
  pixel.show();
}

void connectWiFi() {
  setPixel(C_YELLOW);
  Serial.printf("Connecting to WiFi '%s' ", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    if (millis() - start > 20000) {           // re-issue begin() if stuck
      Serial.print(" [retry] ");
      WiFi.disconnect();
      WiFi.begin(WIFI_SSID, WIFI_PASS);
      start = millis();
    }
  }
  Serial.print(" connected. IP: ");
  Serial.println(WiFi.localIP());
}

void connectMQTT() {
  if (mqtt.connected()) return;
  setPixel(C_YELLOW);
  Serial.print("Connecting to Adafruit IO... ");
  int8_t ret = mqtt.connect();               // returns 0 on success
  if (ret == 0) {
    Serial.println("connected.");
    setPixel(C_GREEN);
  } else {
    Serial.print("failed: ");
    Serial.println(mqtt.connectErrorString(ret));
    setPixel(C_RED);
    mqtt.disconnect();
    delay(3000);                             // brief backoff; loop() will retry
  }
}

void setup() {
  Serial.begin(115200);
  pixel.begin();
  pixel.setBrightness(40);
  setPixel(C_BLUE);

  unsigned long t0 = millis();
  while (!Serial && (millis() - t0 < 2000)) { delay(10); }  // let USB serial attach
  Serial.println("\n\n=== ESP32-S3 Feather + SHT45 -> Adafruit IO ===");

  Wire.begin();                              // STEMMA QT: SDA=3, SCL=4
  if (!sht4.begin()) {
    Serial.println("SHT4x NOT found -- check the STEMMA QT cable/sensor.");
    setPixel(C_RED);
    while (!sht4.begin()) { delay(1000); Serial.println("  retrying SHT4x..."); }
  }
  Serial.printf("SHT4x found. Serial: 0x%08lX\n", (unsigned long)sht4.readSerial());
  sht4.setPrecision(SHT4X_HIGH_PRECISION);
  sht4.setHeater(SHT4X_NO_HEATER);

  if (maxlipo.begin()) {
    haveBattery = true;
    Serial.printf("MAX17048 battery: %.2f V, %.1f %%\n", maxlipo.cellVoltage(), maxlipo.cellPercent());
  } else {
    Serial.println("MAX17048 battery monitor not found.");
  }

  connectWiFi();
  net.setInsecure();                         // skip TLS cert validation (simple + reliable)
  connectMQTT();
}

bool firstReading = true;
unsigned long lastPublish = 0;

void loop() {
  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  connectMQTT();

  unsigned long now = millis();
  if (firstReading || (now - lastPublish >= PUBLISH_INTERVAL_MS)) {
    firstReading = false;
    lastPublish = now;

    sensors_event_t humidity_evt, temp_evt;
    if (sht4.getEvent(&humidity_evt, &temp_evt)) {
      float tC = temp_evt.temperature;
      float rh = humidity_evt.relative_humidity;
      Serial.printf("Temp: %.2f C   RH: %.2f %%   ", tC, rh);

      bool ok = false;
      if (mqtt.connected()) {
        bool ok1 = tempFeed.publish(tC);
        bool ok2 = humFeed.publish(rh);
        ok = ok1 && ok2;
        if (haveBattery) {
          float vbat = maxlipo.cellVoltage();
          float soc = maxlipo.cellPercent();
          Serial.printf("Batt: %.2f V %.1f %%   ", vbat, soc);
          battVFeed.publish(vbat);
          battPctFeed.publish(soc);
        }
      }
      if (ok) { Serial.println("-> published to Adafruit IO"); setPixel(C_GREEN); }
      else    { Serial.println("-> publish FAILED (will retry)"); setPixel(C_RED); }
    } else {
      Serial.println("SHT4x read failed");
      setPixel(C_RED);
    }
  }

  // Service MQTT between publishes to keep the connection alive.
  mqtt.processPackets(500);
  delay(100);
}
