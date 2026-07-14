# Oppsett: varslingsgrenser + push

Denne guiden setter opp temperatur-varsling ende-til-ende: grenser settes i appen, en
planlagt Cloud Function poller datakilden hvert minutt og sender **Time-Sensitive** push
via FCM til iOS (og senere Android). Alt du gjør i kode ligger allerede i repoet — dette er
konsoll-/CLI-stegene som krever dine egne kontoer.

Arkitektur og beslutninger: se `~/.claude/plans/jeg-trenger-1-partitioned-seahorse.md`.

## 0. Forutsetninger
- Betalt Apple Developer-konto (team `E5M8T2CHME`) — allerede på plass.
- Node 22 (for `functions/`).
- Firebase CLI: `npm install -g firebase-tools` og `firebase login`.

## 1. Firebase-prosjekt
1. Opprett prosjekt i <https://console.firebase.google.com>.
2. Sett prosjekt-ID i `.firebaserc` (bytt ut `esp-temp-CHANGEME`), eller kjør `firebase use --add`.
3. **Oppgrader til Blaze** (Pay-as-you-go). Cloud Functions v2, Scheduler og Secret Manager
   krever det. Reelt forbruk her er ~0 kr (godt innenfor gratis-kvotene).

## 2. Registrer iOS-appen i Firebase
1. Firebase-konsoll → «Legg til app» → iOS, bundle-id **`no.brathen.esptemp`**.
2. Last ned `GoogleService-Info.plist` og lagre den som:
   ```
   apple/Sources/App/GoogleService-Info.plist
   ```
   (Git-ignorert. XcodeGen sin `Sources/App`-glob tar den med automatisk — kjør
   `xcodegen generate` på nytt etterpå. Mal: `apple/GoogleService-Info.plist.example`.)

## 3. APNs-nøkkel → Firebase (ellers leveres ingen iOS-push)
1. Apple Developer → Certificates, Identifiers & Profiles → **Keys** → lag en **APNs Auth Key (.p8)**.
   Noter **Key ID**. Team ID er `E5M8T2CHME`.
2. Firebase-konsoll → Project settings → **Cloud Messaging** → Apple app config → last opp
   `.p8` med Key ID + Team ID. (Én `.p8` dekker både sandbox og produksjon.)

## 4. Slå på innloggingsmetoder
Firebase-konsoll → **Authentication** → Sign-in method:
- **Apple** (primær for iOS).
- **Email/Password** (for Android/ikke-Apple senere).

## 5. Adafruit IO-nøkkel som secret
```bash
cd functions
firebase functions:secrets:set ADAFRUIT_IO_KEY   # lim inn jonharald sin AIO-nøkkel
```
Nøkkelen ligger kun i Secret Manager — aldri i appen.

## 6. Deploy regler + funksjoner

Konto-/medlemskaps-modellen krever **streng rekkefølge**: migrer eksisterende enheter
_før_ reglene deployes, ellers blir alle enheter ulesbare (reglene krever `memberUids`,
og eier-sjekkene krever `users/{uid}.accountId`).

```bash
cd functions && npm install          # første gang

# (1) MIGRER først — fyller accounts/*, users.accountId, devices.ownerAccountId/
#     memberAccountIds/memberUids fra legacy ownerUid.
GOOGLE_APPLICATION_CREDENTIALS=./sa.json GCLOUD_PROJECT=temptracker-54c75 \
  node scripts/migrate-memberUids.mjs

cd ..
# (2) deretter regler, (3) deretter funksjoner
firebase deploy --only firestore:rules
firebase deploy --only functions
```
`pollDevices` kjører i `europe-west1` hvert minutt. Callables (`resolveAccount`,
`shareDevice`, `unshareDevice`) deployes samtidig, også i `europe-west1`.

Sett også Firebase Auth til å tillate flere kontoer per e-post:
**Authentication → Settings → User account linking → «Create multiple accounts for each
identity provider»** (uten dette kolliderer Google-innlogging med en eksisterende
Apple-konto på samme e-post).

## 7. Seed enhets-dokumenter (v1: dine egne enheter)
For hver fysiske sensor, opprett et dokument `devices/{deviceId}` (konsoll eller script) med
`ownerUid` = din Firebase Auth-uid (finnes under Authentication → Users etter første innlogging):

```jsonc
// devices/bilen  (seed disse feltene)
{
  "ownerUid": "<din-uid>",
  "name": "Bilen",
  "source": "adafruitio",
  "sourceConfig": { "username": "jonharald", "feedKey": "temperature" },
  "thresholds": { "minC": 5, "maxC": 30, "enabled": true }
}
```
Kjør deretter migreringsskriptet (steg 6.1) — det fyller automatisk `ownerAccountId`,
`memberAccountIds` og `memberUids` fra `ownerUid`. Klienten leser enheter via
`memberUids array-contains uid`.

- `feedKey` er feed-nøkkelen, evt. gruppe-kvalifisert (`default.temperature`).
- `state/current` opprettes automatisk av funksjonen ved første poll.
- Grensene kan endres fra appen etterpå; `enabled: false` skrur av varsling.

### Identitet + deling
- **Samme verifiserte e-post = samme konto:** logger du inn med Apple (iOS) og Google
  (Android) på samme e-post, samler `resolveAccount` begge innlogginger til én konto
  automatisk (ingen manuell handling). Android ser da dine enheter uten deling.
- **Ulik e-post:** eier deler eksplisitt med `shareDevice`-callable, eller admin kjører
  `node scripts/migrate-memberUids.mjs --device <id> --add-email <e-post>`
  (evt. `--add-uid <uid>`).

## 8. Bygg appen til en fysisk enhet
1. `xcodegen generate` i `apple/` (etter at plist-en er på plass).
2. Åpne `apple/EspTemp.xcodeproj` i Xcode. Automatisk signering skal ta med capabilities fra
   `Supporting/EspTemp.entitlements`: Push Notifications, Time Sensitive Notifications,
   Sign in with Apple, App Groups.
3. Kjør på en **fysisk iPhone** (remote push virker ikke pålitelig i simulator).
4. Logg inn (Apple eller e-post) → godta varsler når du blir spurt.
5. Bekreft at FCM-token dukker opp i Firestore under `users/{uid}/fcmTokens/…`.

## 9. Test ende-til-ende
1. I appen: åpne enheten under «Varsling», sett **Maks** lavere enn nåværende temperatur, lagre.
2. Innen ~1 minutt skal et **Time-Sensitive**-varsel komme. Test at det bryter gjennom en
   Fokus-modus (bekrefter interruption-level + entitlement).
3. Sett Maks tilbake over temperaturen → du får ett «normal igjen»-varsel.

### Lokal test uten enhet (logikk)
```bash
cd functions
npm test                     # ren tilstandsmaskin (evaluate)
```
Emulator + manuell poll (Functions-emulatoren kjører ikke planlagte jobber automatisk):
```bash
firebase emulators:start --only functions,firestore,auth
# i functions:shell kan runPoll(...) kalles direkte mot seedet data
```

## Viktige driftsnotater
- **Release-bygg:** `aps-environment` i `EspTemp.entitlements` står på `development`. For
  TestFlight/App Store må den settes til `production`.
- **Adafruit IO-tak:** gratis = 10 feeds (~2 enheter). Flere enheter krever betalt Adafruit IO+
  *eller* overgangen til nRF Cloud. Firebase-siden skalerer gratis til 50-60 enheter.
- **Bytte datakilde (nRF Cloud):** legg til en `NrfCloudDataSource` i
  `functions/src/datasource/` og et `case "nrfcloud"` i `functions/src/datasource/index.ts`.
  Sett `source: "nrfcloud"` på enhets-dokumentene. Ingenting annet endres.
- **Cooldown:** re-varsler tidligst hvert 15. min mens en enhet blir værende i alarm
  (`COOLDOWN_MS` i `functions/src/index.ts`).
