# Plan: iPhone-app + Apple Watch-komplikasjon

## Mål
Vise temperatur (og fuktighet) fra Adafruit IO
- i en **iPhone-app** (nåverdi + graf over historikk), og
- som en **komplikasjon på Apple Watch** (urskive), pluss en liten klokke-app.

Data hentes fra Adafruit IO sitt REST-API (samme feeds som ESP32-en publiserer til:
`temperature` og `humidity` under bruker `jonharald`).

## Status: hva som allerede er satt opp ✅
Alt under `apple/` er scaffoldet og **bygger for simulator** (verifisert med `xcodebuild`, BUILD SUCCEEDED):
- **XcodeGen** (`apple/project.yml`) genererer Xcode-prosjektet → `.xcodeproj` er git-ignorert.
- **3 targets** + delt kode:
  - `EspTemp` – iOS-app (SwiftUI): nåverdi-fliser + Swift Charts-historikk + innstillinger.
  - `EspTempWatch` – watchOS-app (SwiftUI): stor nåverdi, pull-to-refresh.
  - `EspTempComplication` – WidgetKit-extension: komplikasjon i alle accessory-familier
    (`accessoryCircular` gauge, `accessoryCorner`, `accessoryInline`, `accessoryRectangular`).
  - `Sources/Shared/` – kompileres inn i alle: `AdafruitIOClient` (async REST), `TemperatureStore`
    (`@Observable` view-model), `CredentialStore` (App Group + Keychain).

### Generere/bygge lokalt
```sh
cd apple
xcodegen generate          # lager EspTemp.xcodeproj fra project.yml
open EspTemp.xcodeproj      # eller bygg fra kommandolinja:
xcodebuild -scheme EspTemp -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Arkitektur
```
Adafruit IO REST  ──X-AIO-Key──▶  AdafruitIOClient (Sources/Shared)
                                        │
             ┌──────────────────────────┼───────────────────────────┐
        TemperatureStore            (samme klient)             TempProvider
        (iOS + watch UI)                                   (komplikasjon-timeline)
             │                                                     │
        EspTemp (iOS)   ──embed──▶  EspTempWatch (watch)  ──embed──▶ EspTempComplication
```
- Én delt Swift-kildekatalog kompileres inn i hvert target (enkelt, ingen framework-embedding).
- Nøkkel/brukernavn/feeds skrives i iOS-appens innstillinger og lagres i **Keychain + App Group**,
  slik at komplikasjonen kan lese dem. Se «Signering» for forbeholdet om App Group.

## ⚠️ Beslutning som må avklares før enhet: Apple Developer-konto
Komplikasjonen leser innloggingen via **App Group** (`group.no.aksell.esptemp`). App Groups (og delt
Keychain) provisjoneres **kun med betalt Apple Developer Program** ($99/år) på ekte enhet. To veier:

- **A) Betalt konto (anbefalt):** App Group virker; nåværende design brukes uendret. Ryddigst og sikrest.
- **B) Gratis Apple-ID:** ingen App Group. Fallback: legg nøkkel/bruker i en git-ignorert
  `Secrets.xcconfig` som bakes inn i alle tre targets ved bygging (komplikasjonen bruker da samme
  innbakte nøkkel som appen). Mister «skriv inn i appen»-flyten for klokka, men fungerer uten konto.
  Alternativt: sett feeden **public** i Adafruit IO så komplikasjonen leser uten nøkkel.

👉 **Si hvilken du har**, så tilpasser jeg kode + entitlements deretter. Simulator fungerer uansett.

## Signering & kjøring på ekte iPhone + Apple Watch
1. `cd apple && xcodegen generate && open EspTemp.xcodeproj`.
2. For hvert target → **Signing & Capabilities** → velg **Team** (din Apple-ID). Bundle-ID-prefiks er
   `no.aksell.esptemp` (endres i `project.yml` hvis ønskelig — f.eks. til din personlige domenestil).
3. (Konto A) Bekreft **App Groups**-capability med `group.no.aksell.esptemp` på alle tre targets.
4. Koble iPhone (med paret Apple Watch), velg den som mål, **Run**. Watch-appen følger med.
5. På klokka: hold inne urskiva → **Rediger** → legg til **Temp**-komplikasjonen i et felt.

## Komplikasjon: oppdatering
- WidgetKit `TimelineProvider` henter siste verdi og planlegger neste oppdatering ~20 min fram
  (`.after(...)`). watchOS budsjetterer bakgrunnsoppdateringer (~40–70/dag), så «hvert 30. sek» på klokka
  er ikke realistisk — komplikasjonen viser siste hentede verdi og friskes opp jevnlig.
- Når klokke-appen åpnes, kaller den `WidgetCenter.reloadAllTimelines()` for en fersk verdi.
- iOS-appen kaller samme ved lagring av innstillinger.

## Gjenstående arbeid (faser)
1. **Avklar konto A/B** (over) → juster credential-deling + entitlements.
2. **Kjør på dine enheter** – velg Team, verifiser at appen henter data (bruk `jonharald` + AIO-nøkkel),
   legg komplikasjon på urskiva.
3. **Polering iOS-app:** min/max i dag, fuktighetsgraf, «sist sett»-status, feilhåndtering/tom-tilstand,
   app-ikon + accent-farge.
4. **Komplikasjon-polering:** fintune familiene (tint, gauge-range fra faktiske min/max), tekst når
   nøkkel mangler, evt. fuktighet i `accessoryRectangular`.
5. **iOS Lock Screen / Hjem-skjerm-widget (valgfritt):** samme accessory-views → eget iOS widget-target.
6. **Robusthet:** offline/cache siste verdi, tidssone på grafen, enhetsvalg °C/%.
7. (Nice-to-have) **Push i sanntid:** Adafruit IO kan sende webhooks/IFTTT → APNs for umiddelbar
   komplikasjons-oppdatering ved store endringer. Større arbeid; vurderes senere.

## Filstruktur (apple/)
```
apple/
  project.yml                     XcodeGen-spesifikasjon (kilde til .xcodeproj)
  Sources/
    Shared/                       AdafruitIO.swift, Credentials.swift, TemperatureStore.swift
    App/                          EspTempApp, ContentView, SettingsView
    Watch/                        EspTempWatchApp, WatchContentView
    Complication/                 ComplicationWidget (provider + views + bundle)
  Supporting/                     *.entitlements, Complication-Info.plist
```
