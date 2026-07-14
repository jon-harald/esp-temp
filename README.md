# esp-temp

Home temperature monitoring: an **Adafruit Feather ESP32-S3 + SHT45** sensor publishes temperature +
humidity to **Adafruit IO**, viewable on the web, on **iPhone** (+ Apple Watch complication), and on
**Android** (+ home-screen widget). A **Firebase Cloud Function** polls Adafruit IO and sends push
alerts (FCM) when a device crosses its temperature thresholds.

## Repo layout
```
esp-temp/
├── firmware/            ESP32-S3 firmware (reads SHT45 + MAX17048 → publishes to Adafruit IO)
│   └── arduino/esp_temp/    Arduino sketch (running on the board)
├── apple/               iPhone + Apple Watch app (SwiftUI, XcodeGen)
│   ├── project.yml          run `xcodegen generate` to create EspTemp.xcodeproj
│   └── Sources/             Shared / App / Widget / Watch / Complication
├── android/             Android app + home-screen widget (Kotlin, Jetpack Compose, Glance)
│   └── app/src/main/…       open the `android/` folder in Android Studio
├── functions/           Firebase Cloud Functions (TS): poll + alert push, account + sharing callables
│   └── scripts/             migrate-memberUids.mjs (one-time schema migration + sharing bootstrap)
├── firestore.rules      Firestore security rules (account-based membership)
└── docs/
    ├── apple-app-plan.md    plan + status for the Apple app
    └── push-setup.md        Firebase project + alert/push + account model setup
```

## Identity model
A person's logins (Apple on iOS, Google on Android, email/password) are unified into one **account**
by *verified email* — same verified email ⇒ same user (ready for billing). Devices are owned by an
account and can be **shared** with other accounts by email. See [`docs/push-setup.md`](docs/push-setup.md).

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
- **Android app:** open the `android/` folder in Android Studio. Before building, register an Android
  app (package `no.brathen.esptemp`) in the Firebase project, add debug + release SHA-1/SHA-256, and
  download `google-services.json` into `android/app/` (git-ignored; template at
  `android/app/google-services.json.example`). Enable Google sign-in and "multiple accounts per email".
  ```sh
  cd android && ./gradlew :app:assembleDebug
  ```
- **Backend (functions):** see [`docs/push-setup.md`](docs/push-setup.md). Run the migration, then
  deploy rules + functions (in that order):
  ```sh
  cd functions && npm install && npm test
  # migrate → deploy rules → deploy functions (see push-setup.md §6)
  ```

## Secrets
Secrets are git-ignored, templated as `*.example`: `firmware/**/secrets.*`, `settings.toml`,
`apple/**/Secrets.xcconfig`, `apple/Sources/App/GoogleService-Info.plist`,
`android/app/google-services.json`, `android/keystore.properties`. The Adafruit IO key for the
Cloud Function lives in Firebase Secret Manager (`ADAFRUIT_IO_KEY`), never in a client.
