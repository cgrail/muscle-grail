# Muscle Grail: plan

Track sets and reps on iPhone or Apple Watch. Plans are created on the Mac.
Everything works offline, because the gym has no internet. Sync happens in the background.

## Requirements

- Gym once a week. Take either the phone or the watch, and it shows the latest plans and history.
- Sync must not depend on opening an app.
- Logging must be instant and fully offline.
- Workouts go to HealthKit. The watch runs an `HKWorkoutSession`.
- A watch complication shows today's steps and walking km, replacing the step app currently in use.

## Decisions

| Decision | Why |
|---|---|
| SwiftData + CloudKit private database | Least code. The local store works offline, and sync is built in. |
| One local Swift package `Core` for models, sync monitor, HealthKit helpers and shared views | The three apps stay thin. Logic is testable with `swift test`. |
| An exercise is a catalog id: a bundled exercise's id, or a UUID for one the user made | Plans and sets only reference the catalog, so the gym data stays small. Devices create exercises offline without clashing, and a rename keeps the history. |
| The catalog (the user's exercises, descriptions, video links, photos) lives in its own store in the same iCloud container | Photos never weigh on the gym data and sync on their own. CloudKit has no priority setting, so this is as close to "lower priority" as it gets. |
| Exercise picker from [free-exercise-db](https://github.com/yuhonas/free-exercise-db): 876 exercises, public domain, a photo for each. Free text adds an exercise of your own. | Consistent names across devices, which is what history matches on. The JSON is bundled (1 MB). Photos load from GitHub, because bundling all of them would add about 100 MB. |
| One record per logged set, never edited | Two devices can't conflict over a set. Last-writer-wins only affects plan edits. |
| Every change is also stored as an action (a `Change`, as JSON in an `Action` record) and applied from it | The log can rebuild or re-apply the model, whatever the schema does later. Each action carries its app's format version: an older app keeps training, and leaves plan editing to an update. |
| On the Mac, exercises can be added by describing them, through Apple's on-device Foundation Model with a catalog search tool | Free, private, offline, and it understands German. Its small context can't hold the 876 exercises, so it looks names up. Voice is macOS dictation into the same field. Needs Apple Intelligence. |
| Claude edits plans through an MCP server inside the Mac app (Streamable HTTP on 127.0.0.1, off by default) | No extra process or shared store: the tools use the app's own context and actions. Claude Code connects directly, Claude Desktop through `mcp-remote`. |
| HealthKit step observer (`enableBackgroundDelivery`, hourly) instead of `BGAppRefreshTask` | New steps wake iPhone and Watch in the background all day. Each wake gives CloudKit a chance to sync and refreshes the complication. One mechanism covers both jobs. |
| The complication reads HealthKit directly | No App Group or shared store is needed. |
| Watch: steppers instead of the Digital Crown | The crown already pages between exercises. |
| iPhone saves the workout with `HKWorkoutBuilder`; the watch uses `HKWorkoutSession` | The phone has no heart rate sensor. On the watch, the session keeps the app frontmost and running for the whole workout, and records heart rate and calories. |
| Only the device that ran the workout writes to HealthKit, and stores the UUID in `Workout.healthKitID` | No duplicate workouts in Health. |
| Minimum OS 26 on all platforms | All APIs used exist there. |

## How a device stays current without being opened

1. **CloudKit silent push.** A change on any device wakes the others, which pull the change in. This is the main path, e.g. Mac edit → iPhone and Watch.
2. **HealthKit step deliveries, about hourly.** These are background wakes. A wake that cold-launches the app always runs a CloudKit import. `SyncMonitor.waitUntilIdle()` keeps the app awake until sync finishes, up to 20 s.
3. **Steps complication on the active watch face.** This raises the watch app's background budget to up to 4 wakes per hour, and gives one-tap launch in the gym.
4. **`HKWorkoutSession`** keeps the watch app alive during the workout. Changes queued offline are uploaded at the next wake at home.

Each device shows the last successful sync: on iOS and watchOS in the footer of the Train list, on the Mac in the toolbar.

Three things stop background sync completely:
- swiping the app away in the app switcher
- Low Power Mode
- Background App Refresh turned off

## Layout

```
MuscleGrail.xcodeproj   folders are synced: new files in App/, Watch/, Complication/ are picked up automatically
App/                    iOS + macOS app (one multiplatform target). Train, Plans, History
Watch/                  watchOS app. Plan picker, one page per exercise, HKWorkoutSession
Complication/           WidgetKit complication: today's steps + km
Core/                   Swift package: models, Store + SyncMonitor, Health, shared views, exercise catalog, tests
Config/                 entitlements and Info.plists
```

Bundle IDs come from one build setting, `BUNDLE_ID_PREFIX = de.grails.musclegrail`.
The CloudKit container is `iCloud.de.grails.musclegrail`, which is defined in `Core/Sources/Core/Store.swift` and `Config/*.entitlements`.

## First run

1. Open `MuscleGrail.xcodeproj` in Xcode. Team `3Z7QAPFM7G` is preset with automatic signing.
2. Check the container name before the first run. **CloudKit container IDs are permanent** and can't be deleted, so rename it now if you want a different one.
3. For each target, open Signing & Capabilities and let Xcode register the App IDs. Under iCloud, make sure `iCloud.de.grails.musclegrail` is checked. If it's red, click the refresh button so Xcode creates it.
4. Run `MuscleGrail` on *My Mac* and create a plan.
5. Run `MuscleGrail` on the iPhone and allow Health access. The watch app installs with it; you can also run the `MuscleGrailWatch` scheme directly on the watch.
6. Open the watch app once and allow Health access. Add the **Steps** complication to your main watch face.

Builds installed from Xcode use CloudKit's **Development** environment. With a paid account they run for a year.
TestFlight and App Store builds use **Production**, and data doesn't cross between the two environments. Before the first TestFlight build:
- deploy the schema in the CloudKit Console
- from then on, only add model fields; never rename or delete them

## Acceptance tests (the real requirement)

- [ ] **A — Mac to devices.** Edit a plan on the Mac and quit it. Don't touch the phone or watch for 24 h. Then turn on airplane mode on both and open each one. The edit is there.
- [ ] **B — Watch to everything.** With airplane mode on, log a workout on the watch only. At home, turn airplane mode off and open nothing. Within 24 h the workout shows on the Mac and iPhone.
- [ ] **C — Phone to everything.** Same as B with the phone only.
- [ ] **D — Health.** Each workout appears once in Health. The watch workout has heart rate.
- [ ] **E — Complication.** It matches the step count in the Health app within about 15 min.

## Status

- [x] Core: models, sync monitor, HealthKit helpers, shared views, exercise catalog. Unit tests, the 10 use-case tests and the sync test pass (`cd Core && swift test`), every file above 90% line coverage.
- [x] English and German, through String Catalogs in every target.
- [x] Plan editor: "Add exercise" opens a searchable catalog with photos (search by name, muscle or equipment).
- [x] The iOS app builds with the watch app and complication embedded, and the macOS app builds.
- [x] Smoke test in the iPhone simulator: the CloudKit store opens and the Health permission sheet appears.
- [ ] Run on real devices, then acceptance tests A–E.
- [ ] App icons.

## Known risks and fallbacks

- **Two stores mirror into one CloudKit container** (gym data and the catalog). If that misbehaves on devices, move the catalog to a container of its own.
- **There is no public "sync now" API.** A wake of an app that is already running but suspended may not start a CloudKit import. Silent pushes still cover the common case. If test A or B fails:
  - **Watch lags behind:** have the phone push the latest state to the watch with WatchConnectivity `updateApplicationContext`. It works over Bluetooth, no internet needed.
  - **Sync stays unreliable:** move to `CKSyncEngine`, whose fetch and send calls can be awaited in any background wake. It means a lot more code.
- **Locked watch.** HealthKit can't be read while the watch is locked, so the complication then shows the last value read today.

## Skipped (not asked for)

- Exercise photos during a workout (only in the picker) and offline photos
- Rest timer and live heart rate display
- Workout crash recovery
- Live phone↔watch mirroring during a workout
- iPad layout
- Siri and App Intents
- Plan sharing
- Unit settings (only kg, in 2.5 kg steps)
