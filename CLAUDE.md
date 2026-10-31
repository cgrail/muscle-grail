# Muscle Grail

Offline-first gym tracker. iPhone and Apple Watch log sets, a Mac app edits plans, and SwiftData syncs everything through the CloudKit private database. The gym has no internet, so every user action works offline.

Read [PLAN.md](PLAN.md) before changing sync, the data model, or HealthKit. It holds the decisions, known risks, and the acceptance tests that define "done".

## Platform roles

- Mac: create and maintain plans. Full plan editing lives here, laid out like Apple Music (`MacRootView`): a sidebar with Train, History, the exercise library and every plan as a playlist; a plan opens as a table to edit in place (`PlanPage`). It can also train, like the iPhone, but saves nothing to Health (macOS has no HealthKit). Exercises can be added by describing them, typed or dictated (`PlanAssistant`, Apple's on-device model with a catalog search tool; the model's side has no tests, so check it by hand). Claude can create and extend plans through MCP, switched on in Settings (see below).
- Watch: the gym device. It logs sets and makes small adjustments to the running workout: add a set, delete a set. Plan creation and editing stay on the Mac. Its info screen (i) shows the version, the commit (`GitCommit`, stamped into the built Info.plist by the watch target's "Stamp Git Commit" phase) and the plan changes that synced to it (`PlanChanges`, without undo there). Its Activity, which the complication opens (`widgetURL`), shows steps and the activity grid (`ActivityGrid`, Core).
- iPhone and Mac: Settings → About shows the version and the commit (`AppInfo`, stamped by the app target's own "Stamp Git Commit" phase), linked to the commit on GitHub, and a link to the repository.
- Every platform is fast: each tap answers from the local store. Network calls, sync waits and heavy work stay off the main actor and out of user paths.

## Build and test

- `xcode-select` points at the Command Line Tools, so prefix every `swift` / `xcodebuild` call with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Core tests: `cd Core && ./fetch-catalog.sh && swift test`. The exercise catalog isn't in git (see Exercise catalog); the script downloads it once.
- Compile check, no signing: `xcodebuild -project MuscleGrail.xcodeproj -scheme MuscleGrail -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`. This also builds the embedded watch app and complication. Use `-destination 'platform=macOS'` for the Mac app.
- An unsigned build traps inside CloudKit at launch. To launch in the simulator, sign ad hoc: `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`. A simulator without an iCloud account gets no plans: tick `-sampleData` in the MuscleGrailWatch scheme, and the watch adds a plan to train with while its store has none (`SampleData`, simulator builds only). Real sync needs signed device builds (team `3Z7QAPFM7G`).
- Done means `swift test` passes and the compile check succeeds for iOS (which includes the watch) and macOS. The user runs the UI tests by hand.
- GitHub Actions (`.github/workflows/build.yml`) runs those three checks on every pull request and push to `main`, on the `macos-26` runner with its newest stable Xcode. It fetches the catalog, then runs Core's tests with `xcodebuild test -scheme Core`, because SwiftPM before Xcode 27 doesn't compile String Catalogs. It doesn't measure coverage.

## Tests

- Coverage: every file in `Core` at 90%+ lines, 100% is the goal. Measure from `Core/`: `swift test --enable-code-coverage`, then `xcrun llvm-cov report .build/debug/CoreTests.xctest/Contents/MacOS/CoreTests -instr-profile .build/debug/codecov/default.profdata -ignore-filename-regex='\.build|Tests'`.
- The app targets have no test target, so logic goes in `Core` and the views in `App/` and `Watch/` stay thin. `Health.swift` compiles only for iOS and watchOS, so it is missing from the macOS coverage report: keep it a thin HealthKit wrapper.
- Core views get smoke tests that render them in a window (`ViewsTests.render`). The accessibility tree is empty under `swift test`, so assert on the store, not on what's on screen.
- One behavior, one test: changing a behavior should break exactly one test. Each test asserts only the behavior its name states. Shared setup goes in helpers.
- Integration tests: exactly 10, one per most-used use case, plus one sync test. To cover a new use case, replace the least important one. They live in `Core/Tests/CoreTests/Integration/` and run a use case end to end through `Store` and the models.
- The sync test focuses on phone and watch: sets logged offline on one device show up on the other in history and prefill, with no duplicates. CloudKit doesn't run under `swift test`, so simulate the other device's records arriving in the local store. Real sync is checked by acceptance tests A–C in PLAN.md.

## Project shape

- The Xcode project uses synchronized folders. Add a file by creating it in `App/`, `Watch/` or `Complication/`; it joins that target automatically. Edit `project.pbxproj` only for targets, build settings or capabilities.
- `App/` is one multiplatform target (iOS + macOS). Gate platform-specific code with `#if os(iOS)` / `#if os(macOS)`.
- `Complication/` builds twice: as `StepsComplication` inside the watch app, and as `StepsWidget`, the iPhone's Home Screen and Lock Screen widget, inside the iPhone app only. Gate watch-only families with `#if os(watchOS)`; both targets share its string catalogs, and both read the daily goals from the iPhone app's iCloud key-value store (`dailyGoals`), so their entitlement names the app's store. So does the watch app's.
- In the app's tabs, navigate with `navigationDestination(item:)` or plain `NavigationLink`s, never a typed `NavigationStack(path:)`. The sidebar-adaptable `TabView` (Mac, iPad) compares navigation paths across tabs and crashes on a typed one (`AnyNavigationPath.Error.comparisonTypeMismatch`).
- Code used by more than one target lives in the `Core` package: models, `Store` + `SyncMonitor`, `Health`, shared SwiftUI views, the exercise catalog.
- Concurrency: app targets use Swift 5 mode with default actor isolation `MainActor`. `Core` uses Swift 6 strict concurrency and is nonisolated by default.
- `Config/` holds entitlements and Info.plists and belongs to no target.
- The app icon comes from `Design/icon-source.jpg`. `Design/Icon.swift` turns it into the icons in `App/` and `Watch/`'s `Assets.xcassets` (iPhone and watch full bleed without alpha, every macOS size) and `Design/icon.png`. After replacing the image, run `swift Design/Icon.swift` from the repo root.
- Files stay under 300 lines. Split by feature before a file crosses that, one feature per file, named after it. Subfolders inside a synchronized folder join the target too.

## Localization

- English and German. Every user-facing string lives in a String Catalog (`Localizable.xcstrings`, `InfoPlist.xcstrings` for Info.plist strings) with German filled in. `LocalizationTests` fails on any string without German.
- `xcodebuild` doesn't add new strings to a catalog. After the build, run `xcrun xcstringstool sync <catalog> --stringsdata <files>` with the target's `*.stringsdata` from DerivedData `Build/Intermediates.noindex/…/Objects-normal/arm64/`, then translate the new keys.
- Strings shown from `Core` need `bundle: .module`; without it SwiftUI looks them up in the app's catalog.
- An exercise's `name` stays English: Claude (MCP) and the plan assistant look exercises up by it. The apps show `label` and `steps`, which RepDB has in German (`name_de`, `instructions_de`). Where a machine reads a name (MCP, the video search), pass `localized: false` to `exerciseName`.
- The catalog's muscles, levels, equipment and categories are RepDB's English keys (`pectoralis_major`, `pull_up_bar`); they show through `catalogTerm`, from entries added by hand (`extractionState: manual`) to Core's `Localizable.xcstrings`. After a catalog update, `LocalizationTests` names every new term without German, and every exercise RepDB brought without it.

## Data model (CloudKit rules)

- Ask before any model migration, and never make one on your own: a model or field added to a `SchemaV<n>`, unshipped versions included, or a new schema version. Describe the change and why it is needed, then wait for the user's approval. In that same message, remind the user that the schema must be deployed to Production before the next TestFlight or App Store upload, or sync stops for every user (see Releases).
- Every property has a default or is optional, and every relationship is optional with an inverse. No `@Attribute(.unique)`. Ordering lives in an `order: Int` field. A model that breaks a rule fails the store at launch.
- Model changes are always backwards compatible: add models and fields, never rename, retype or delete one. Devices update at different times (the Mac apart from the iPhone and watch), so an older App Store build must still read what a newer one syncs, and CloudKit's Production schema can't drop a field.
- Every shipped schema version stays in the code (`SchemaV1.swift`, …), frozen, and `MigrationPlan` migrates a store from any of them to the newest. A version is frozen once a TestFlight or App Store build has shipped it; until then the newest one may change in place, even by renaming or removing (with approval; then reset the Development CloudKit schema and delete development data). To change a frozen model, follow the steps on `MigrationPlan` in `Models.swift`. Stages are `.lightweight` only: CloudKit stores can't run custom ones.
- `MigrationTests` enforce both: a store written by every version opens in the newest with its data, every version keeps each field of the one before with its type, and every field may be missing.
- An exercise is its catalog id (`PlanItem.exerciseID`, `LoggedSet.exerciseID`): a bundled exercise's id, or a UUID string for one the user made, so devices create exercises offline without clashing. History and prefill match on it, so a rename keeps the history.
- Every model change goes through `ModelContext.record(_:)` (`Actions.swift`), which stores the `Change` in its log (`Action`, or `CatalogAction` for the catalog) and applies it. Views edit through Core functions (their bindings call them), never a model property. `replay(into:)` re-applies the log: into an empty store it rebuilds the model, into the live one it changes nothing. `ActionTests` checks both.
- `Change` formats are frozen like schema versions: never rename a case or label, give a new field an optional type, and bump `Change.version` with every new case or field. `ActionTests` keeps the JSON of every version-1 change, which must keep decoding; add the same for each new version.
- The Mac backs up both logs as one JSON file (`Backup`) into the folder picked in Settings → General (`BackupFolder`), at launch and after each save or sync. Its entries keep each action's raw payload, so a backup taken by any version can be replayed by a later one. Restore (`Backup.restore`) replaces the whole store, both logs included, with a backup; the deletions sync, so every device ends up with it.
- Training works on every version, forever: starting a workout, logging, deleting a set and finishing never check a version or ask for an update. Only plan editing locks while a newer app version has recorded actions (`Action.newer`), and asks the user to update.
- `LoggedSet` is append-only: one record per set, deleted to undo.
- Only one workout runs at a time: the apps start no plan while `isTraining`. `startWorkout` itself never refuses, because two offline devices can each start one and both must still apply.
- `ModelContext.log` saves immediately, because the watch app can be killed between sets.

## Sync and HealthKit

- SwiftData has no "sync now" API. Background wakes come from CloudKit silent pushes and the HealthKit step observer (`Health.observeSteps`). The observer must be registered at every launch, background launches included. `SyncMonitor.waitUntilIdle()` holds a wake open until sync settles.
- Plans shared with a training partner sync through `PartnerSync` (App, so the iPhone and the Mac) with `CKSyncEngine` in the `Partner` zone, beside SwiftData: the owner's engine on the private database, the partner's on the shared one. What goes out and how what comes in applies are in Core (`Partner.swift`, the records in `PartnerRecords.swift`), with tests; the engine itself is checked by acceptance tests F–K. Its state is the file `Partner.json` in Application Support, which keeps its name and fields. The HealthKit step wake syncs it too.
- A workout goes to HealthKit only from the device that ran it. That device stores the UUID in `Workout.healthKitID`.
- The CloudKit container `iCloud.de.grails.musclegrail` is permanent: Apple can't delete or rename it.

## Releases and the App Store

- The apps ship through the App Store when the user releases a version; the watch app and complication ship inside the iPhone app. A push to `main` releases nothing.
- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are set once in the project's build settings, so every target shares them (the watch app's version must match the iPhone app's). Each upload needs a higher `CURRENT_PROJECT_VERSION`.
- TestFlight and App Store builds use CloudKit's Production environment. Before uploading a build with a model change, deploy the schema to Production in the CloudKit Console. First run the app from Xcode with the MuscleGrail scheme's `-initializeCloudKitSchema` argument ticked (`CloudKitSchema`, debug builds only): it creates every SwiftData record type and field in Development, then quits. Syncing alone creates only the fields it uploaded a value for, and Production refuses records with a type or field it lacks: downloads keep working while every upload fails with "Failed to modify some records". The `Partner` zone's record types come from `CKSyncEngine`, not SwiftData, so they appear in Development only once a debug build has shared plans. Before submitting for review, check that the console's Deploy Schema Changes lists nothing left to deploy. To try a schema change in TestFlight before deploying it, set the entitlement `com.apple.developer.icloud-container-environment` to `Development`, and set it back to `Production` before the App Store build. Background: [why sync stops after App Store release](https://fatbobman.com/en/snippet/why-core-data-or-swiftdata-cloud-sync-stops-working-after-app-store-login/).
- Export compliance ([Apple](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)): the app's Info.plist sets `ITSAppUsesNonExemptEncryption` to NO, so uploads skip the encryption question. That holds while the apps use only Apple's encryption (HTTPS, CloudKit) and hashing (SHA-256 in `GymBook.id`). Adding encryption of our own means revisiting it.
- Saved data: the `UserDefaults` keys `lastSync`, `lastChange`, `lastExport` and `unsentPlans` (`SyncMonitor`), `day`, `steps`, `km` (the complication), `mcpServer` (the Mac's Claude switch), `backupFolder` (the bookmark of the Mac's backup folder) and `AppleLanguages` (the language switch on iPhone and Mac, Apple's own key read at launch), and the iCloud key-value keys `goalSteps` and `goalKm` (daily goals) and `partnerAlwaysBoth` (whether changes to shared exercises are always for both), keep their names and meaning, so an update reads what the old version saved.
- [CHANGELOG.md](CHANGELOG.md) gets an entry in the same commit as every change a user would notice, under `## <MARKETING_VERSION> (current)`. Say what the app does now, not what the diff did; refactors that change nothing visible stay out. When `MARKETING_VERSION` is bumped, the top section is closed and a new current one opens above it.
- `WHATS-NEW.md` is the user-facing cut for App Store Connect's "What's New", in English and German, written when a version ships, not per commit. Plain text: App Store Connect rejects bullets, emoji and typographic dashes or quotes there (umlauts are fine).

## Exercise catalog

- The catalog is [RepDB](https://github.com/RepDB/exercise-dataset)'s free dataset: 650 exercises in English, German and Spanish, at the commit `CatalogExercise.repdbCommit` pins. Its license allows in-app use with attribution but forbids republishing the dataset, and this repo is public, so it is never committed: `Core/fetch-catalog.sh` downloads `exercises.json` into `Core/Sources/Core/RepDB/` (ignored by git). The app and watch schemes run it as a build pre-action, CI as a step; run it once before `swift test`. A pre-action that can't download doesn't fail the build: the app then has an empty catalog.
- Keep "Exercise data by RepDB (repdb.co)" visible, linked to https://repdb.co: `Credits` in Settings on the iPhone and the Mac, and the README. RepDB's images may not be fed to generative models, so never hand them to the plan assistant or Claude.
- To update the catalog, change `repdbCommit`. Its `id`s are catalog ids that plans and sets refer to, so check that none disappeared.
- The user's `CatalogEntry`s sit on top: their own exercises, and their name, description, video link and photo for any exercise. They live in the separate Catalog store of the same iCloud container (`Store.configurations`) with their own log, so the gym store stays small. Photos are stored as JPEGs of at most 1024 px (`Photo.jpeg`).
- Weights step through what the exercise's equipment really comes in (`Weights`), never by a fixed amount.
- Weights are stored in kg. An exercise's unit (`CatalogEntry.unit`, kg or lb, because some machines show pounds) only changes how they show and are typed: show one with `WeightUnit.format`, edit one with `WeightStepper`, never with a fixed "kg".
- Show a name with `ExerciseName` (`exerciseName(_:entry:)` outside views). A custom exercise whose entry hasn't synced yet shows a placeholder.
- Illustrations load from RepDB's GitHub at the pinned commit (see `CatalogExercise.imageURL`), so the picker needs internet to show them. Training never does: it shows only photos on the device, the user's own and the illustrations `PhotoCache` downloaded (512 px) while the workout picker had network.

## GymBook

- `GymBook.read` (Core) reads GymBook's log export (XML in UTF-16, German dates, weights like "38,00 kg" or "130,00 lb") or its full backup (a `.database` file, its Core Data store as SQLite: `GymBookBackup`) into a `GymBook.File`: the logs, the workouts, and the plans, the backup's own or, from the export, each workout name's newest workout. The export writes the history in the log export's format. On the Mac, File → Import from GymBook… and History's GymBook menu start `GymBookImporter`, which shows what a file brings first (`GymBookImport`): its plans to pick (GymBook's active ones ticked), the history, and each exercise beside the one it becomes, with its photo. A click opens `ExerciseChooser`: the likeliest first, then the catalog to search, with the selected one's `ExercisePreview` beside the list. `gymBookMatches` finds one by name, else by letter-trigram likeness of its English, German or Spanish name (`CatalogExercise.closest`, 0.85 or more); the others show the closest as alternatives, and `ExerciseMatcher` (App) lets Apple's on-device model guess among those. It seldom answers that none fits, so the sheet marks its guesses to check; it has no tests, so check it by hand. Reading, matching and importing run off the main actor.
- An imported workout and its sets get ids from their day, workout name and position (`GymBook.id`), so importing the same file again adds nothing. Keep those keys as they are.
- This repo is public: never commit a GymBook export or backup (keep them in the ignored `temp/`). Tests use the made-up `gymBookSample` and `gymBookBackupSample`.

## Claude (MCP)

- `MCP` (Core) answers JSON-RPC with four tools: `list_plans`, `search_exercises`, `create_plan`, `add_exercises`. They edit through the same Core functions as the app, so edits are recorded as actions and wait for an update after newer actions. In a plan shared with the training partner, `add_exercises` adds the user's own exercises unless its `shared` argument, or the always-both setting, says for both.
- `MCPServer` (Core, macOS) serves it over Streamable HTTP at `http://127.0.0.1:7428/mcp` while the Mac app runs and Settings → Claude is on. It listens on the loopback interface only and refuses requests with a foreign `Origin` (DNS rebinding). The Mac app needs `com.apple.security.network.server` for it.
- `MCPTests` call the real server over HTTP on a free port.

## Workflow

- The backlog is `todo.md`, worked through with the `/todo` skill. Each item gets its own commit, and done items are ticked `[x]` and kept.
- Commit messages use an imperative subject of about 60 characters with no scope prefix ("Add searchable exercise catalog picker"). Add a body only when the reason isn't obvious.
