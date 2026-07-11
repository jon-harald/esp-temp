# Firmware — ESP32-S3 Feather + SHT45 → Adafruit IO

Reads temperature + humidity from an **Adafruit SHT45** (product 5665) over STEMMA QT (I²C) plus
**battery voltage + %** from the board's onboard **MAX17048** fuel gauge, on an **Adafruit Feather
ESP32-S3** (4 MB Flash / 2 MB PSRAM, product 5477), and publishes to **Adafruit IO** over MQTT/TLS
every 30 s. Feeds: `temperature`, `humidity`, `esp-battery-v`, `esp-battery-pct`.

- Dashboard: <https://io.adafruit.com/jonharald/dashboards/esp32-temperatur>
- Raw feed:  <https://io.adafruit.com/jonharald/feeds/temperature>

## Two firmware options
The board currently runs the **CircuitPython** version. Both self-heal: they power the STEMMA QT bus and
wait for the SHT45 to appear before publishing.

| | CircuitPython (`circuitpython/`) | Arduino (`arduino/esp_temp/`) |
|---|---|---|
| Edit | drag `code.py` onto the CIRCUITPY drive | recompile + reflash |
| Status | **running now** | compiled, ready to flash |

## Hardware
- Feather ESP32-S3 ↔ SHT45 via a STEMMA QT cable (I²C, address `0x44`).
- Onboard **MAX17048 LiPo fuel gauge at I²C `0x36`** — reports cell voltage + state-of-charge (no wiring;
  it's on the built-in bus). On USB power with no battery it reads the VBAT rail (~4.2 V / >100 %).
  Also a handy sanity check: if an I²C scan shows `0x36` but not `0x44`, the bus is fine and the SHT45
  cable/connection is the problem (this bit us once — cable was loose).
- STEMMA QT / I²C power is gated by **GPIO7** (must be HIGH; Arduino core does it in `initVariant()`,
  CircuitPython `code.py` sets `board.I2C_POWER`).
- NeoPixel status: blue=boot, yellow=connecting, green=publishing OK, red=error/waiting for sensor.
- WiFi SSID is `JH_SL` (underscore) on 2.4 GHz — ESP32-S3 has no 5 GHz.

## Board reset quirk (important)
Native USB (USB-Serial/JTAG), **no RTS→EN wiring**, so esptool's default "reset via RTS pin" does **not**
reboot it:
1. Enter download mode: **hold `BOOT`, tap `RESET`, release `BOOT`** (→ `/dev/cu.usbmodem1101`).
2. Boot the app after flashing: use **`esptool --after watchdog-reset`**, not the default.

## Arduino: build & flash
```sh
arduino-cli compile --fqbn esp32:esp32:adafruit_feather_esp32s3 --output-dir build arduino/esp_temp

# After BOOT+RESET (board in download mode on /dev/cu.usbmodem1101):
esptool --chip esp32s3 --port /dev/cu.usbmodem1101 \
  --before no-reset --after watchdog-reset \
  write-flash 0x0 build/esp_temp.ino.merged.bin
```
FQBN defaults are correct: USB CDC on boot, PSRAM (QSPI) enabled, 4 MB flash.
Secrets in `arduino/esp_temp/secrets.h` (git-ignored; template `secrets.h.example`).

## CircuitPython: install (currently running)
CircuitPython 10.2.1. `code.py` + libs live on the CIRCUITPY drive. Required libs in `CIRCUITPY/lib/`:
`adafruit_sht4x`, `adafruit_max1704x`, `adafruit_bus_device`, `adafruit_register`, `adafruit_minimqtt`,
`adafruit_connection_manager`, `adafruit_requests`, `adafruit_ticks`, `adafruit_ntp`, `neopixel`,
`adafruit_pixelbuf`.

> **If CIRCUITPY mounts read-only** (macOS fskit can latch a FAT "dirty bit" after interrupted writes,
> and the board may stop exposing the drive): **power-cycle the board** (unplug/replug USB) — a clean
> re-mount clears it. Copy files with `COPYFILE_DISABLE=1 cp -X …` to avoid `._` resource-fork churn.
Secrets in `CIRCUITPY/settings.toml` (template `circuitpython/settings.toml.example`).

### MiniMQTT + Adafruit IO TLS gotchas (handled in `code.py`)
- **`is_ssl=True`** on the MQTT client — MiniMQTT defaults it to `False` even with an `ssl_context` +
  port 8883, sending plaintext to the TLS port → connect hangs. (Main gotcha.)
- **`socket_timeout=5, recv_timeout=25`** — TLS handshake needs a wide recv window (`recv_timeout` must be
  strictly greater than `socket_timeout`; default 10 was too short).
- **`mqtt_client.loop(timeout=5)`** — loop timeout must be ≥ `socket_timeout`.
- Set the clock via `adafruit_ntp` before connecting (TLS cert-date validation).

## Serial monitor
115200 baud over USB, e.g. `arduino-cli monitor -p <port> -c baudrate=115200`.
