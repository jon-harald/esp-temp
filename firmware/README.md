# Firmware — ESP32-S3 Feather + SHT45 → Adafruit IO

Reads temperature + humidity (**Adafruit SHT45**, product 5665, STEMMA QT I²C) plus **battery
voltage + %** (onboard **MAX17048** fuel gauge) on an **Adafruit Feather ESP32-S3** (product 5477),
and publishes to **Adafruit IO** with a single HTTPS POST. Feeds: `temperature`, `humidity`,
`esp-battery-v`, `esp-battery-pct`. Purpose: **dog-in-car temperature safety monitor**.

- Dashboard: <https://io.adafruit.com/jonharald/dashboards/esp32-temperatur>
- Firmware: **Arduino** (`arduino/esp_temp/`).

## Power design: adaptive deep sleep
Wake → read → publish → **deep sleep** (~0.1 mA). The interval adapts to temperature — dense readings
exactly when a parked car turns dangerous:

| Temperature | Wake interval |
|---|---|
| ≥ 30 °C | 60 s |
| 25–30 °C | 2 min |
| < 25 °C | 5 min |
| battery < 10 % | intervals ×3 |
| failed cycle | 60 s (3+ fails → 10 min backoff) |

Also: RTC-cached DHCP lease + AP BSSID (fast reconnect ~1 s), 80 MHz CPU, MAX17048 hibernated,
NeoPixel blink-only, one HTTPS request, serial-wait only on cold boot, 25 s awake budget, watchdog.
Expected life: **weeks to ~2 months** (LiPo size + how often it runs hot).

> **USB port disappears while sleeping** — the board comes and goes each cycle. Normal.

## Credentials live in NVS (not in the binary)
So the compiled `.bin` is safe to host publicly for OTA. **Provision once** over serial (115200):
```
PROV {"ssid":"YOUR_SSID","pass":"YOUR_PASS","user":"AIO_USER","key":"aio_xxx"}
```
On first boot with empty NVS the board waits in provisioning mode (slow blue blink) for that line,
saves to NVS, and reboots. NVS survives OTA, deep sleep and power loss (only `esptool erase-flash`
wipes it). To re-provision: send the `PROV` line again over serial any time it's awake and idle at boot.

## Over-the-air updates (pull-based, failure-tolerant)
The board checks a small manifest **hourly** and updates itself — it never needs to be reachable:

1. `firmware/ota-manifest.json` (served raw from `main`) holds `{version, url, md5}`.
2. If `version` differs from the running build, it downloads the `.bin` from `url`.
3. **Robustness:** a partial/corrupt download is rejected (the running firmware is untouched — a
   half-flash is impossible); the `.bin`'s MD5 and the image's built-in SHA are verified; after
   applying, the new firmware must complete one healthy publish within 3 boots or it **auto-rolls
   back** to the previous version (survives boot-loops and power loss, state in NVS); a rolled-back
   version is remembered and skipped until a new one ships; a watchdog catches hangs; OTA failures
   never block monitoring.

### Shipping an update
```sh
# 1. bump FIRMWARE_VERSION in arduino/esp_temp/config.h, then build:
arduino-cli compile --fqbn esp32:esp32:adafruit_feather_esp32s3:PartitionScheme=min_spiffs \
  --output-dir build arduino/esp_temp

# 2. publish the app image as a release asset:
gh release create fw-1.2.0 build/esp_temp.ino.bin -t "fw-1.2.0" -n "notes"

# 3. update firmware/ota-manifest.json (version, url, md5 = `md5 -q build/esp_temp.ino.bin`)
#    and push to main. The board pulls it within the hour.
```

## Board reset quirk (important)
Native USB (USB-Serial/JTAG), **no RTS→EN wiring** → esptool's default "reset via RTS" does **not**
reboot it:
1. Download mode: **hold `BOOT`, tap `RESET`, release `BOOT`** (→ `/dev/cu.usbmodem*`).
2. Boot after flashing: **`esptool --after watchdog-reset`**, not the default.

## First flash / partition change (USB, one time)
OTA needs the OTA-capable `min_spiffs` partition scheme, so the first flash goes over USB:
```sh
arduino-cli compile --fqbn esp32:esp32:adafruit_feather_esp32s3:PartitionScheme=min_spiffs \
  --output-dir build arduino/esp_temp

# after BOOT+RESET (download mode):
esptool --chip esp32s3 --port /dev/cu.usbmodem1101 \
  --before no-reset --after watchdog-reset \
  write-flash 0x0 build/esp_temp.ino.merged.bin
# then provision (see above). All later updates are OTA.
```
`merged.bin` = full image (bootloader + partitions + app) for USB. `esp_temp.ino.bin` = app-only
image, the artifact used for OTA. FQBN defaults are otherwise correct (USB CDC on boot, PSRAM, 4 MB).

## Serial monitor
115200 baud over USB: `arduino-cli monitor -p <port> -c baudrate=115200`.
