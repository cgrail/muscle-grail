# Muscle Grail: plan

Track sets and reps on iPhone or Apple Watch. Plans are created on the Mac.
Everything works offline, because the gym has no internet. Sync happens in the background.

## Requirements

- Gym once a week. Take either the phone or the watch, and it shows the latest plans and history.
- Sync must not depend on opening an app.
- Logging must be instant and fully offline.
- Workouts go to HealthKit. The watch runs an `HKWorkoutSession`.
- A watch complication shows today's steps and walking km, replacing the step app currently in use.
- Train with a partner: share plans with one invite, change them for both at once, and keep each person's own weights and history.

## Decisions

| Decision | Why |
|---|---|
| SwiftData + CloudKit private database | Least code. The local store works offline, and sync is built in. |
| One local Swift package `Core` for models, sync monitor, HealthKit helpers and shared views | The three apps stay thin. Logic is testable with `swift test`. |
| An exercise is a catalog id: a bundled exercise's id, or a UUID for one the user made | Plans and sets only reference the catalog, so the gym data stays small. Devices create exercises offline without clashing, and a rename keeps the history. |
| The catalog (the user's exercises, descriptions, video links, photos) lives in its own store in the same iCloud container | Photos never weigh on the gym data and sync on their own. CloudKit has no priority setting, so this is as close to "lower priority" as it gets. |
| Exercise picker from [RepDB](https://github.com/RepDB/exercise-dataset)'s free dataset: 650 exercises with illustrations, steps and German names. Free text adds an exercise of your own. | Consistent ids across devices, which is what history matches on, and German without translating it ourselves. Its license forbids republishing the dataset, so it is downloaded at build time into the app (2 MB), never committed. Illustrations load from GitHub, because bundling them would add about 20 MB to every target. |
| One record per logged set, never edited | Two devices can't conflict over a set. Last-writer-wins only affects plan edits. |
| Every change is also stored as an action (a `Change`, as JSON in an `Action` record) and applied from it | The log can rebuild or re-apply the model, whatever the schema does later. Each action carries its app's format version: an older app keeps training, and leaves plan editing to an update. |
| On the Mac, exercises can be added by describing them, through Apple's on-device Foundation Model with a catalog search tool | Free, private, offline, and it understands German. Its small context can't hold the 650 exercises, so it looks names up. Voice is macOS dictation into the same field. Needs Apple Intelligence. |
| Claude edits plans through an MCP server inside the Mac app (Streamable HTTP on 127.0.0.1, off by default) | No extra process or shared store: the tools use the app's own context and actions. Claude Code connects directly, Claude Desktop through `mcp-remote`. |
| HealthKit step observer (`enableBackgroundDelivery`, hourly) instead of `BGAppRefreshTask` | New steps wake iPhone and Watch in the background all day. Each wake gives CloudKit a chance to sync and refreshes the complication. One mechanism covers both jobs. |
| The activity chart: gym days from the store's workouts plus Health's strength workouts (any app), and each day's steps and distance from Health against the daily goals, read when it shows | A watch workout reaches the iPhone's Health over Bluetooth long before its record syncs through iCloud, so a gym day shows right away. Nothing from Health is stored. Workouts the app saved itself are matched by `healthKitID`, so they aren't counted twice. Walks count through steps and distance. |
| Daily goals live in iCloud's key-value store; each day's steps and distance come from Health | Tiny settings need no model or migration, and still reach every device. The widget and the complication read the same store for their progress ring. |
| The iPhone widget is the complication's code built again for iOS (`StepsWidget`) | One source for both. The iPhone app reloads it on every HealthKit step wake, like the watch does its complication. |
| The complication reads HealthKit directly | No App Group or shared store is needed. |
| Watch: steppers instead of the Digital Crown | The crown already pages between exercises. |
| iPhone saves the workout with `HKWorkoutBuilder`; the watch uses `HKWorkoutSession` | The phone has no heart rate sensor. On the watch, the session keeps the app frontmost and running for the whole workout, and records heart rate and calories. |
| Only the device that ran the workout writes to HealthKit, and stores the UUID in `Workout.healthKitID` | No duplicate workouts in Health. |
| Minimum OS 26 on all platforms | All APIs used exist there. |
| Plans are shared with a training partner through one zone-wide `CKShare`: a `Partner` zone in the sharer's private database, which the partner sees in their shared database | One invite covers every plan in the zone, now and later. No backend: CloudKit carries it, and each person keeps their own iCloud account. SwiftData can't share, so the zone syncs beside it with `CKSyncEngine`. |
| The zone carries plan changes in the `Change` format, never models | The format is frozen and versioned, and applying a change twice is already safe. Each side applies it to its own plan through `record(_:)`, so the shared part needs no model migration. |
| The partner's copy of a shared plan keeps the plan's and its exercises' ids | A change applies to the partner's plan as it is, with no mapping between ids. The two stores live in different iCloud accounts, so the ids never clash. |
| Only a plan's structure is shared: adding, removing, moving and reordering exercises, and adding, renaming and deleting plans | Partners train the same routine with different weights. Sets, reps, weights and the order of the plan list stay personal, and prefill already comes from each person's own history. |
| A structure change to a shared plan asks "Only me" or "Me and <partner>", unless Settings says "Always both" | Most changes are for both, but sometimes one person does a variation. |

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

## Sharing plans with a training partner

Two people who train together share plans, each with their own Apple ID, history and weights.

- **One invite.** Settings → Training partner → Share plans, on the Mac or the iPhone, makes the `Partner` zone and its zone-wide share and opens the share sheet. The partner accepts the link on their iPhone or Mac. Nothing is ever sent again: a plan that joins the zone later reaches them over the same share. The owner can stop sharing and the partner can leave. Both keep their plans as they are then; the plans just stop changing together.
- **All plans or chosen plans.** The choice lives in the zone, so it is the same for both.
  - *All plans* (the default): every plan of the person who shares, and every plan either of them adds from then on, is shared.
  - *Chosen plans:* only the plans someone shares.
  - In both modes, a plan that isn't shared has "Share with <partner>" in its menu, a shared one has "Stop sharing", and shared plans show a badge. Plans the partner had before accepting stay theirs until they share one. Switching to all plans later shares the plans of whoever switches.
- **The zone** holds `SharedPlan` records (one per shared plan, named by its id), `SharedChange` records (one per change sent: `payload`, `version`, `date`, and for a new exercise the sender's `sets` and `reps`), and one `PartnerSettings` record (all or chosen plans).
- **Sharing a plan** writes its structure into the zone: `addPlan`, then `addExercise` for each exercise. On the partner's side it goes to the end of the plan list.
- **Editing.** On a shared plan, a structure change asks "Only me" or "Me and <partner>", named from the share's participant, or follows "Always both" (Settings → Training partner, kept in iCloud's key-value store, so all of one person's devices follow it). With both, the same `Change` goes into the zone as well as into the local log. A rename asks once, when the name is done, not for every key. Changes to sets, reps and weight never ask and never reach the zone.
- **Moving an exercise** to another plan is one change (`moveExercise`), so it asks once, and the partner's copy keeps their own sets, reps and weight. If only one of the two plans is shared, the partner sees a removal or an addition.
- **A new exercise** on the partner's side starts with the sender's sets and reps. Its weight comes from the partner's own last set of that exercise, else 0 kg. An exercise of the sender's own brings its name along, as an `editExercise` with only the name; its description, video and photo stay with the sender.
- **Receiving.** The iPhone and the Mac run the engine. The watch doesn't: it gets the changed plan through its own iCloud, as always. A device applies only the changes the other person wrote, oldest first, through `record(_:)`, so they are in its log, its backup and its replay, and it never sends them back. A device's own changes reach that person's other devices through SwiftData; applying them from the zone as well could undo a later "Only me" change. A change to a plan or exercise this side doesn't have changes nothing. A reorder moves only the exercises both have; one that only this side has stays after the exercise it followed.
- **Offline.** An edit applies locally at once. `CKSyncEngine` keeps the outgoing change on the device and sends it when the network is back. Its state and a cache of the zone (shared plans, mode, the partner's name) are saved in a file on the device, so the question works offline. A device that has never fetched the zone doesn't know which plans are shared, so its edits stay "Only me".
- **Wakes.** The engine has its own CloudKit subscription, so a change from the partner wakes the app with a silent push, like SwiftData's. The HealthKit step wake also fetches the zone. All of this runs off the main actor.
- **Versions.** A received change this app version can't read waits in the cache until an update, and plan editing locks meanwhile, like for `Action.newer`. Training never waits.
- **Claude (MCP).** `create_plan` and `add_exercises` share their changes when the call passes `shared: true`, or when Settings says "Always both"; otherwise they change only your plans.

## Layout

```
MuscleGrail.xcodeproj   folders are synced: new files in App/, Watch/, Complication/ are picked up automatically
App/                    iOS + macOS app (one multiplatform target). iPhone: tabs Train, Plans, History. Mac: an Apple Music-style sidebar
Watch/                  watchOS app. Plan picker, one page per exercise, HKWorkoutSession
Complication/           WidgetKit: today's steps + km, as the watch complication and the iPhone widget
Core/                   Swift package: models, Store + SyncMonitor, Health, shared views, exercise catalog, tests
Config/                 entitlements and Info.plists
Design/                 the icon's source image, and Icon.swift, which makes every icon size from it
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
- deploy the schema in the CloudKit Console, the `Partner` zone's record types included
- from then on, only add model fields; never rename or delete them

## Acceptance tests (the real requirement)

- [ ] **A — Mac to devices.** Edit a plan on the Mac and quit it. Don't touch the phone or watch for 24 h. Then turn on airplane mode on both and open each one. The edit is there.
- [ ] **B — Watch to everything.** With airplane mode on, log a workout on the watch only. At home, turn airplane mode off and open nothing. Within 24 h the workout shows on the Mac and iPhone.
- [ ] **C — Phone to everything.** Same as B with the phone only.
- [ ] **D — Health.** Each workout appears once in Health. The watch workout has heart rate.
- [ ] **E — Complication.** It matches the step count in the Health app within about 15 min.
- [ ] **F — One invite.** Share all plans from the Mac; the partner accepts the one link on their iPhone. Every plan shows on their iPhone and watch. A plan added on the Mac a week later reaches them without another invite.
- [ ] **G — Both, offline.** With the Mac offline, move curls from one shared plan to another and choose "Me and <partner>". Go online, and don't touch the partner's devices. Within 24 h their iPhone and watch show curls in the new plan, with their own weight.
- [ ] **H — Only me.** Change sets, reps and weights, and add an exercise with "Only me". The partner's plans don't change.
- [ ] **I — Both at once.** With both iPhones offline, each person removes a different exercise from the same shared plan, for both. Back online, both exercises are gone on all devices, and nothing is doubled.
- [ ] **J — Stop.** Stop sharing. Both keep their plans as they were, and changes no longer cross.

## Status

- [x] Core: models, sync monitor, HealthKit helpers, shared views, exercise catalog. Unit tests, the 10 use-case tests and the sync test pass (`cd Core && swift test`), every file above 90% line coverage.
- [x] English and German, through String Catalogs in every target.
- [x] Plan editor: "Add exercise" opens a searchable catalog with photos (search by name, muscle or equipment).
- [x] The iOS app builds with the watch app and complication embedded, and the macOS app builds.
- [x] Smoke test in the iPhone simulator: the CloudKit store opens and the Health permission sheet appears.
- [ ] Run on real devices, then acceptance tests A–E.
- [ ] Plan sharing with a training partner (`todo.md`), then acceptance tests F–J with two Apple IDs.
- [x] App icons: a flexed arm lifting a dumbbell, made from `Design/icon-source.jpg` by `Design/Icon.swift`.

## Known risks and fallbacks

- **Two stores mirror into one CloudKit container** (gym data and the catalog). If that misbehaves on devices, move the catalog to a container of its own.
- **There is no public "sync now" API.** A wake of an app that is already running but suspended may not start a CloudKit import. Silent pushes still cover the common case. If test A or B fails:
  - **Watch lags behind:** have the phone push the latest state to the watch with WatchConnectivity `updateApplicationContext`. It works over Bluetooth, no internet needed.
  - **Sync stays unreliable:** move to `CKSyncEngine`, whose fetch and send calls can be awaited in any background wake. It means a lot more code.
- **SwiftData and `CKSyncEngine` in one private database.** SwiftData mirrors its own zone, and the engine fetches only `Partner` (`FetchChangesOptions.scope`). If they get in each other's way, move sharing to a container of its own. That container is permanent too, so name it once.
- **Sharing is only checked by hand.** CloudKit doesn't run under `swift test`, so the engine stays a thin wrapper, like `Health.swift`, and the rules (what is shared, how a received change applies) live in `Core` with tests. Acceptance tests F–J need two Apple IDs, on devices or simulators.
- **Locked watch.** HealthKit can't be read while the watch is locked, so the complication then shows the last value read today.

## Skipped (not asked for)

- Exercise photos during a workout (only in the picker) and offline photos
- Rest timer and live heart rate display
- Workout crash recovery
- Live phone↔watch mirroring during a workout
- iPad layout
- Siri and App Intents
- Sharing history, weights, photos or descriptions with a training partner
- Linking a plan the partner made on their own to a shared one: it needs a mapping between ids, so a model migration
- Unit settings (only kg, in 2.5 kg steps)
