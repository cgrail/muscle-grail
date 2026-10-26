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
- Every plan change shows in a history, with who made it, and can be undone. A plan can go back to an old version.

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
| The zone carries plan changes in the `Change` format, never models | The format is frozen and versioned, and applying a change twice is already safe. Each side applies it to its own plan through `record(_:)`, so it lands in that side's log too. |
| The partner's copy of a shared plan keeps the plan's and its exercises' ids | A change applies to the partner's plan as it is, with no mapping between ids. The two stores live in different iCloud accounts, so the ids never clash. |
| A shared plan has the same exercises in the same order for both; each exercise is for both or one person's own | Partners train side by side, so position 5 is the same moment for both, even when one does curls there and the other bench press. Every change to the plan's exercises crosses, so the two lists never drift apart. |
| Sets, reps, weights and the order of the plan list stay personal | Partners train the same routine with different weights. Prefill already comes from each person's own history. |
| Adding, removing, replacing or moving an exercise that is for both asks "Only me" or "Me and <partner>", unless Settings says "Always both". Reordering and renaming never ask | Most changes are for both, but sometimes one person does a variation. The order is always for both, since they train together. |
| The log of changes is the plans' history: per plan and across plans, with who made each change. Undo and restoring an old version record new changes | The log already holds every plan change, so the history needs no second record. Recording instead of rewinding keeps the log append-only, so an undo syncs, reaches the partner, and can be undone in turn. |
| New fields go into `SchemaV1` in place, with no new schema version and no migration stage (the user's call, 2026-10-26) | Nothing has shipped yet. From the first TestFlight build on, the rules in CLAUDE.md apply. |
| Weights are stored in kg everywhere; an exercise's unit, `CatalogEntry.unit` (kg or lb, set with `setUnit`, `Change.version` 3, approved 2026-10-26, in `SchemaV1` in place), only changes how they show, are typed and step | Some machines in the gym show kg and others lb. Sets, targets, changes, statistics and Claude keep one unit, so switching an exercise's unit changes no data. |

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
- **The zone** holds `SharedPlan` records (one per shared plan, named by its id), `SharedChange` records (one per change: `payload`, `version`, `date`, `batch`, for a new exercise the sender's `sets` and `reps`, and for an exercise the sender made its `name`), and one `PartnerSettings` record (all or chosen plans).
- **Sharing a plan** writes its structure into the zone: `addPlan`, then `addExercise` for each exercise, in order. On the partner's side it goes to the end of the plan list.
- **Same exercises, same order.** Both have every exercise of a shared plan, in one order, so they stay side by side. An exercise is for both, or one person's own (`PlanItem.owner`). One person's own exercise shows greyed in the other's plan, with its owner's name, and the other's training skips it, on the iPhone, the watch and the Mac, as does the plan's summary of what it trains. So at position 5 one can do curls and the other bench press, and moving the first exercise to the end keeps the two at the same place for both.
- **Editing.** Adding, removing, replacing or moving an exercise that is for both asks "Only me" or "Me and <partner>", named from the share's participant, unless Settings → Training partner says "Always both" (kept in iCloud's key-value store, so all of one person's devices follow it). "Only me" keeps the two lists side by side:
  - adding: the new exercise is your own.
  - removing: the exercise becomes the partner's own.
  - replacing: the old exercise becomes the partner's own, and the new one is your own, right after it.
  - moving to another plan: the exercise becomes the partner's own where it was, and goes into the other plan as your own.
- **What never asks.** Your own exercises, reordering and renaming: the order and the name are for both. Sets, reps and weights never ask and never leave your account. Every other change to a shared plan goes into the zone, "Only me" included, so both lists keep the same exercises.
- **Moving and replacing.** Moving an exercise to another plan is one change (`moveExercise`): it asks once, and each side keeps its own sets, reps and weight. If only one of the two plans is shared, the partner sees a removal or an addition. Replacing (`replaceExercise`) keeps the exercise's place; the new exercise's weight comes from each person's own last set of it, else 0 kg.
- **A new exercise** on the partner's side starts with the sender's sets and reps, and its weight from the partner's own last set of it, else 0 kg. An exercise the sender made themselves brings its name along, as an `editExercise` with only the name; its description, video and photo stay with the sender.
- **Receiving.** The iPhone and the Mac run the engine. The watch doesn't: it gets the changed plan through its own iCloud, as always. A device applies only the changes the other person wrote, oldest first, through `record(_:)` with `Action.author` set and the sender's id and date (`ModelContext.receive`), skipping one it already has, so they are in its log, its history and its backup, and it never sends them back. A device's own changes reach that person's other devices through SwiftData; applying them from the zone as well could undo a later change. A change to a plan this side doesn't have changes nothing.
- **Both at once.** Changes made offline on both sides end the same everywhere, whatever order they arrive in. A received rename, reorder or move older than this side's last one of the same plan or exercise is skipped, so the later one wins. A removal wins over a move. Two exercises added at the same position sort by id.
- **Offline.** An edit applies locally at once. What goes out is worked out from the log (`PartnerChange.outgoing`): this person's changes after the last one sent, from the state before each, so nothing made offline is lost. `CKSyncEngine` sends them when the network is back. Its state and a cache of the zone (shared plans, mode, the partner's name) are saved in a file on the device, so the question works offline. A device that has never fetched the zone doesn't know which plans are shared, so its edits stay its own.
- **Wakes.** The engine has its own CloudKit subscription, so a change from the partner wakes the app with a silent push, like SwiftData's. The HealthKit step wake also fetches the zone. All of this runs off the main actor.
- **Versions.** A received change this app version can't read waits in the cache until an update, and plan editing locks meanwhile, like for `Action.newer`. Training never waits.
- **Claude (MCP).** On a shared plan, `add_exercises` adds for both when the call passes `shared: true` or Settings says "Always both"; otherwise the exercises are your own.

## Plan history

Every plan change is an action in the log, so the log is the history of the plans. It works without sharing too.

- **Changes.** A list of plan changes across all plans (on the Mac in the sidebar under Library, on the iPhone from the Plans tab) and for one plan (the Mac's plan page, the iPhone's plan editor). Each entry says what changed, in which plan, when and by whom: "Yesterday · <partner> moved Curls from Push to Pull". Changes to one person's own exercises say so. Workouts and sets aren't in it; History shows those.
- **One entry per edit.** Typing a weight or a name records an action per key, so changes of the same kind to the same exercise or plan, by the same person, in a row, show as one entry. The changes of one undo or restore share `Action.batch` and show as one entry too.
- **Undo.** An entry's Undo records the changes that reverse it, as one batch: the log only grows, the undo syncs, and it can be undone in turn. It reaches whoever the change reached: undoing a change for both undoes it for both, whoever made it. A removed exercise comes back with its id, so each side gets back its own sets, reps and weight from its own log. When the exercise or plan an entry is about is gone, there is nothing to undo, and Undo is off.
- **Old versions.** "Restore this version" on an entry of a plan's history brings the plan back to how it was right after that entry. Core replays the log up to there into an in-memory store, as `replay(into:)` does, and records, as one batch, the changes that turn today's plan into that one: exercises come back (from another plan, if they were moved there), later ones go, the order and the name are as they were, and so are your own sets, reps and weights. On a shared plan everything but the targets goes for both, and the partner keeps their own targets. Undoing the restore brings today's plan back.
- **Off the main actor.** Building the list and an old version walks the log, so it runs in a context of its own off the main actor, and only the result reaches the view.
- Going back for the whole store stays the Mac's backup restore.

## Model changes for sharing and history

Approved on 2026-10-26. Nothing has shipped, so they go into `SchemaV1` in place, with no new schema version and no migration stage. A build may then fail to open the store an older build made on the same device. Instead of crashing at launch (today's `fatalError` in `MuscleGrailApp` and `MuscleGrailWatchApp`), the iPhone, the Mac and the watch then say that this version can't read the data on the device, and offer two choices:

- **Download again** (the default): deletes this device's copy and opens a new store, which fills again from iCloud. iCloud's records still read, because fields were only added.
- **Start from scratch:** after a confirmation that says it can't be undone, deletes this device's copy and the app's data in iCloud, so every device starts empty. The Mac's backup restore brings the data back, because replay reads a backup of any version.

- `PlanItem.owner`: empty for an exercise for both, else whose own it is, this person or the partner. It is relative to the store's person, so one exercise reads "mine" on one side and "theirs" on the other.
- `Action.author`: nil for this person's own changes, else the partner's name, set when a received change is recorded.
- `Action.batch`: the same id for the changes of one undo or restore.
- `Change` gains `moveExercise`, `replaceExercise` and `setOwner`, and `addExercise` an optional owner. An owner in a change is relative to its author ("mine" or "the other's"), so one change reads right on both sides. `Change.version` goes to 2 once, for all of them, and ActionTests keeps their JSON.
- `Backup` entries keep `author` and `batch`.

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
- [ ] **H — Only me.** Change sets, reps and weights: the partner's stay as they are. Add curls "Only me" at position 5 while the partner adds bench press there "Only me": each trains their own and sees the other's greyed. Move the first exercise to the end: curls and bench press stay at the same place for both.
- [ ] **I — Both at once.** With both iPhones offline, each person removes a different exercise from the same shared plan, for both. Back online, both exercises are gone on all devices, and nothing is doubled.
- [ ] **J — Stop.** Stop sharing. Both keep their plans as they were, and changes no longer cross.
- [ ] **K — History.** A day after the partner moved curls from Push to Pull, Pull's history and the history across plans show who moved it and when, on the Mac and the iPhone. Undo puts curls back in Push on every device of both, with each person's own weight. Restoring Push to last week brings back its exercises in their old order with your old weights; the partner keeps theirs.
- [ ] **L — Old store.** Install a build with the changed `SchemaV1` over an older one. It offers both choices instead of crashing. Download again brings the data back. Start from scratch empties the iPhone, the watch and the Mac, and the Mac's backup restore brings everything back.

## Status

- [x] Core: models, sync monitor, HealthKit helpers, shared views, exercise catalog. Unit tests, the 10 use-case tests and the sync test pass (`cd Core && swift test`), every file above 90% line coverage.
- [x] English and German, through String Catalogs in every target.
- [x] Plan editor: "Add exercise" opens a searchable catalog with photos (search by name, muscle or equipment).
- [x] The iOS app builds with the watch app and complication embedded, and the macOS app builds.
- [x] Smoke test in the iPhone simulator: the CloudKit store opens and the Health permission sheet appears.
- [ ] Run on real devices, then acceptance tests A–E.
- [ ] Plan history, and plan sharing with a training partner (`todo.md`), then acceptance tests F–L with two Apple IDs.
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
- Linking a plan the partner made on their own to a shared one: it needs a mapping between their ids. Sharing one of the two and deleting the other does the same, and history matches by exercise.
- Unit settings (only kg, in 2.5 kg steps)
