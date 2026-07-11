# esp-temp

Home temperature monitoring: an **Adafruit Feather ESP32-S3 + SHT45** sensor publishes temperature +
humidity to **Adafruit IO**, viewable on the web, on **iPhone**, and as an **Apple Watch complication**.

## Repo layout
```
esp-temp/
├── firmware/            ESP32-S3 firmware (reads SHT45 + MAX17048 → publishes to Adafruit IO)
│   └── arduino/esp_temp/    Arduino sketch (running on the board)
├── apple/               iPhone + Apple Watch app (SwiftUI, XcodeGen)
│   ├── project.yml          run `xcodegen generate` to create EspTemp.xcodeproj
│   └── Sources/             Shared / App / Watch / Complication
└── docs/
    └── apple-app-plan.md    plan + status for the Apple app
```

## Live data
- Dashboard: <https://io.adafruit.com/jonharald/dashboards/esp32-temperatur>
- Feed: <https://io.adafruit.com/jonharald/feeds/temperature>

## Getting started
- **Firmware:** see [`firmware/README.md`](firmware/README.md). The board currently runs the Arduino
  version and publishes temperature, humidity + battery every ~30 s.
- **Apple app:** see [`docs/apple-app-plan.md`](docs/apple-app-plan.md). Build with:
  ```sh
  cd apple && xcodegen generate && open EspTemp.xcodeproj
  ```
  It builds for the simulator today; running on a real iPhone + Apple Watch needs your Apple-ID Team
  (and, for the shared-credentials complication, a paid Apple Developer account — see the plan).

## Secrets
WiFi/Adafruit-IO secrets are git-ignored (`firmware/**/secrets.*`, `settings.toml`, `Secrets.xcconfig`).
Templates: `*.example`.
