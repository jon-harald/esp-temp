# ESP32-S3 Feather + SHT45 -> Adafruit IO (MQTT/TLS)
# Reads temperature + humidity from an SHT45 (STEMMA QT / I2C) and publishes to
# Adafruit IO every PUBLISH_INTERVAL seconds. Config from settings.toml.
#
# Uses adafruit_minimqtt directly (publishing to "<user>/feeds/<key>"), with a
# generous recv_timeout so the ESP32-S3 TLS handshake to io.adafruit.com completes.
# Robust startup: powers the STEMMA QT bus and waits for the SHT45 to appear,
# so it self-recovers if the sensor is (re)connected.

import os
import time
import ssl
import board
import digitalio
import wifi
import socketpool
import adafruit_sht4x
import adafruit_minimqtt.adafruit_minimqtt as MQTT

PUBLISH_INTERVAL = 30  # seconds

WIFI_SSID = os.getenv("CIRCUITPY_WIFI_SSID")
WIFI_PASSWORD = os.getenv("CIRCUITPY_WIFI_PASSWORD")
AIO_USERNAME = os.getenv("AIO_USERNAME")
AIO_KEY = os.getenv("AIO_KEY")

TEMP_TOPIC = "%s/feeds/temperature" % AIO_USERNAME
HUM_TOPIC = "%s/feeds/humidity" % AIO_USERNAME
BATT_V_TOPIC = "%s/feeds/esp-battery-v" % AIO_USERNAME
BATT_PCT_TOPIC = "%s/feeds/esp-battery-pct" % AIO_USERNAME

# ---- Power the STEMMA QT / I2C port and NeoPixel (defensive) ----
for _name in ("I2C_POWER", "NEOPIXEL_POWER"):
    if hasattr(board, _name):
        try:
            _p = digitalio.DigitalInOut(getattr(board, _name))
            _p.switch_to_output(value=True)
        except Exception as _e:  # noqa: BLE001
            print("power pin", _name, "note:", _e)
time.sleep(0.5)

# ---- Optional NeoPixel status light ----
pixel = None
try:
    import neopixel

    pixel = neopixel.NeoPixel(board.NEOPIXEL, 1, brightness=0.2, auto_write=True)
except Exception as _e:  # noqa: BLE001
    print("NeoPixel not available:", _e)

BLUE, GREEN, RED, YELLOW = (0, 0, 60), (0, 60, 0), (60, 0, 0), (60, 40, 0)


def status(color):
    if pixel is not None:
        try:
            pixel[0] = color
        except Exception:  # noqa: BLE001
            pass


status(BLUE)

i2c = board.STEMMA_I2C()


def scan():
    while not i2c.try_lock():
        pass
    try:
        return i2c.scan()
    finally:
        i2c.unlock()


# ---- Wait for the SHT45 (0x44, or 0x45 for B-variants) ----
sht_addr = None
while sht_addr is None:
    devs = scan()
    for a in (0x44, 0x45):
        if a in devs:
            sht_addr = a
            break
    if sht_addr is None:
        status(RED)
        print("Waiting for SHT45 at 0x44/0x45. I2C devices found:",
              [hex(d) for d in devs], "-- check the STEMMA QT cable.")
        time.sleep(2)

status(YELLOW)
sht = adafruit_sht4x.SHT4x(i2c, address=sht_addr)
sht.mode = adafruit_sht4x.Mode.NOHEAT_HIGHPRECISION
print("Found SHT4x at", hex(sht_addr), "serial:", hex(sht.serial_number))

# ---- Onboard MAX17048 LiPo fuel gauge (I2C 0x36) ----
battery = None
try:
    import adafruit_max1704x

    battery = adafruit_max1704x.MAX17048(i2c)
    print("MAX17048 battery: %.2f V, %.1f %%" % (battery.cell_voltage, battery.cell_percent))
except Exception as _e:  # noqa: BLE001
    print("MAX17048 battery monitor not available:", _e)


def connect_wifi():
    status(YELLOW)
    print("Connecting to WiFi '%s' ..." % WIFI_SSID)
    wifi.radio.connect(WIFI_SSID, WIFI_PASSWORD)
    print("WiFi connected. IP:", wifi.radio.ipv4_address)


connect_wifi()
pool = socketpool.SocketPool(wifi.radio)

# Set the clock via NTP -- TLS certificate validation needs a correct date.
try:
    import rtc
    import adafruit_ntp

    rtc.RTC().datetime = adafruit_ntp.NTP(pool, tz_offset=0).datetime
    print("Time set via NTP")
except Exception as _e:  # noqa: BLE001
    print("NTP time set failed (continuing):", _e)

mqtt_client = MQTT.MQTT(
    broker="io.adafruit.com",
    port=8883,
    username=AIO_USERNAME,
    password=AIO_KEY,
    socket_pool=pool,
    ssl_context=ssl.create_default_context(),
    is_ssl=True,  # REQUIRED: MiniMQTT defaults is_ssl=False, which would send plaintext to the TLS port 8883 and hang
    keep_alive=120,
    # ESP32-S3 TLS handshake to Adafruit IO needs a generous recv window,
    # otherwise the connect times out / hangs (recv_timeout must be > socket_timeout).
    socket_timeout=5,
    recv_timeout=25,
)


def mqtt_connect():
    status(YELLOW)
    print("Connecting to Adafruit IO (MQTT/TLS) ...")
    mqtt_client.connect()
    print("Connected to Adafruit IO")
    status(GREEN)


mqtt_connect()


def reconnect():
    status(YELLOW)
    print("Reconnecting ...")
    try:
        mqtt_client.reconnect()
        status(GREEN)
        return
    except Exception as e:  # noqa: BLE001
        print("reconnect() failed:", e)
    try:
        if not wifi.radio.connected:
            connect_wifi()
        mqtt_client.connect()
        status(GREEN)
    except Exception as e2:  # noqa: BLE001
        print("full reconnect failed:", e2)
        status(RED)
        time.sleep(10)


while True:
    try:
        mqtt_client.loop(timeout=5)  # must be >= socket_timeout (5)
        temperature, humidity = sht.measurements
        temperature = round(temperature, 2)
        humidity = round(humidity, 2)
        print("Temp: %.2f C   RH: %.2f %%" % (temperature, humidity))
        mqtt_client.publish(TEMP_TOPIC, temperature)
        mqtt_client.publish(HUM_TOPIC, humidity)
        if battery is not None:
            try:
                vbat = round(battery.cell_voltage, 2)
                soc = round(battery.cell_percent, 1)
                print("Batt: %.2f V   %.1f %%" % (vbat, soc))
                mqtt_client.publish(BATT_V_TOPIC, vbat)
                mqtt_client.publish(BATT_PCT_TOPIC, soc)
            except Exception as e:  # noqa: BLE001
                print("Battery read error:", e)
        status(GREEN)
    except Exception as e:  # noqa: BLE001
        print("Loop error:", e)
        status(RED)
        reconnect()
    time.sleep(PUBLISH_INTERVAL)
