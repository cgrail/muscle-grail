# Muscle Grail

Offline-first gym tracker. iPhone and Apple Watch log sets, a Mac app edits plans, and SwiftData syncs everything through the CloudKit private database. The gym has no internet, so every user action works offline.

Read [PLAN.md](PLAN.md) before changing sync, the data model, or HealthKit. It holds the decisions, known risks, and the acceptance tests that define "done".

## Platform roles

- Mac: create and maintain plans. Full plan editing lives here. It can also train, like the iPhone, but saves nothing to Health (macOS has no HealthKit). Exercises can be added by describing them, typed or dictated (`PlanAssistant`, Apple's on-device model with a catalog search tool; the model's side has no tests, so check it by hand).
- Watch: the gym device. It logs sets and makes small adjustments to the running workout: add a set, delete a set. Plan creation and editing stay on the Mac.
- Every platform is fast: each tap answers from the local store. Network calls, sync waits and heavy work stay off the main actor and out of user paths.

## Build and test

- `xcode-select` points at the Command Line Tools, so prefix every `swift` / `xcodebuild` call with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Core tests: `cd Core && swift test`.
- Compile check, no signing: `xcodebuild -project MuscleGrail.xcodeproj -scheme MuscleGrail -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`. This also builds the embedded watch app and complication. Use `-destination 'platform=macOS'` for the Mac app.
- An unsigned build traps inside CloudKit at launch. To launch in the simulator, sign ad hoc: `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`. Real sync needs signed device builds (team `3Z7QAPFM7G`).
- Done means `swift test` passes and the compile check succeeds for iOS (which includes the watch) and macOS. The user runs the UI tests by hand.

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
- Code used by more than one target lives in the `Core` package: models, `Store` + `SyncMonitor`, `Health`, shared SwiftUI views, the exercise catalog.
- Concurrency: app targets use Swift 5 mode with default actor isolation `MainActor`. `Core` uses Swift 6 strict concurrency and is nonisolated by default.
- `Config/` holds entitlements and Info.plists and belongs to no target.
- Files stay under 300 lines. Split by feature before a file crosses that, one feature per file, named after it. Subfolders inside a synchronized folder join the target too.

## Localization

- English and German. Every user-facing string lives in a String Catalog (`Localizable.xcstrings`, `InfoPlist.xcstrings` for Info.plist strings) with German filled in. `LocalizationTests` fails on any string without German.
- `xcodebuild` doesn't add new strings to a catalog. After the build, run `xcrun xcstringstool sync <catalog> --stringsdata <files>` with the target's `*.stringsdata` from DerivedData `Build/Intermediates.noindex/…/Objects-normal/arm64/`, then translate the new keys.
- Strings shown from `Core` need `bundle: .module`; without it SwiftUI looks them up in the app's catalog.
- Exercise names stay English: the name is the key for history and prefill, and the catalog data is English only.

## Data model (CloudKit rules)

- Ask before any model migration, and never make one on your own: a model or field added to a `SchemaV<n>`, unshipped versions included, or a new schema version. Describe the change and why it is needed, then wait for the user's approval.
- Every property has a default or is optional, and every relationship is optional with an inverse. No `@Attribute(.unique)`. Ordering lives in an `order: Int` field. A model that breaks a rule fails the store at launch.
- Model changes are always backwards compatible: add models and fields, never rename, retype or delete one. Devices update at different times (the Mac apart from the iPhone and watch), so an older App Store build must still read what a newer one syncs, and CloudKit's Production schema can't drop a field.
- Every shipped schema version stays in the code (`SchemaV1.swift`, …), frozen, and `MigrationPlan` migrates a store from any of them to the newest. A version is frozen once a TestFlight or App Store build has shipped it; until then the newest one may change in place, even by renaming or removing (with approval; then reset the Development CloudKit schema and delete development data). To change a frozen model, follow the steps on `MigrationPlan` in `Models.swift`. Stages are `.lightweight` only: CloudKit stores can't run custom ones.
- `MigrationTests` enforce both: a store written by every version opens in the newest with its data, every version keeps each field of the one before with its type, and every field may be missing.
- An exercise is its catalog id (`PlanItem.exerciseID`, `LoggedSet.exerciseID`): a bundled exercise's id, or a UUID string for one the user made, so devices create exercises offline without clashing. History and prefill match on it, so a rename keeps the history.
- Every model change goes through `ModelContext.record(_:)` (`Actions.swift`), which stores the `Change` in its log (`Action`, or `CatalogAction` for the catalog) and applies it. Views edit through Core functions (their bindings call them), never a model property. `replay(into:)` re-applies the log: into an empty store it rebuilds the model, into the live one it changes nothing. `ActionTests` checks both.
- `Change` formats are frozen like schema versions: never rename a case or label, give a new field an optional type, and bump `Change.version` with every new case or field. `ActionTests` keeps the JSON of every version-1 change, which must keep decoding; add the same for each new version.
- Training works on every version, forever: starting a workout, logging, deleting a set and finishing never check a version or ask for an update. Only plan editing locks while a newer app version has recorded actions (`Action.newer`), and asks the user to update.
- `LoggedSet` is append-only: one record per set, deleted to undo.
- `ModelContext.log` saves immediately, because the watch app can be killed between sets.

## Sync and HealthKit

- SwiftData has no "sync now" API. Background wakes come from CloudKit silent pushes and the HealthKit step observer (`Health.observeSteps`). The observer must be registered at every launch, background launches included. `SyncMonitor.waitUntilIdle()` holds a wake open until sync settles.
- A workout goes to HealthKit only from the device that ran it. That device stores the UUID in `Workout.healthKitID`.
- The CloudKit container `iCloud.de.grails.musclegrail` is permanent: Apple can't delete or rename it.

## Releases and the App Store

- The apps ship through the App Store when the user releases a version; the watch app and complication ship inside the iPhone app. A push to `main` releases nothing.
- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are set once in the project's build settings, so every target shares them (the watch app's version must match the iPhone app's). Each upload needs a higher `CURRENT_PROJECT_VERSION`.
- TestFlight and App Store builds use CloudKit's Production environment. Before uploading a build with a model change, deploy the schema to Production in the CloudKit Console.
- Saved data: the `UserDefaults` keys `lastSync` (`SyncMonitor`) and `day`, `steps`, `km` (the complication) keep their names and meaning, so an update reads what the old version saved.
- [CHANGELOG.md](CHANGELOG.md) gets an entry in the same commit as every change a user would notice, under `## <MARKETING_VERSION> (current)`. Say what the app does now, not what the diff did; refactors that change nothing visible stay out. When `MARKETING_VERSION` is bumped, the top section is closed and a new current one opens above it.
- `WHATS-NEW.md` is the user-facing cut for App Store Connect's "What's New", in English and German, written when a version ships, not per commit. Plain text: App Store Connect rejects bullets, emoji and typographic dashes or quotes there (umlauts are fine).

## Exercise catalog

- `Core/Sources/Core/exercises.json` is [free-exercise-db](https://github.com/yuhonas/free-exercise-db), public domain, bundled unchanged. To update it, replace the file with that repo's `dist/exercises.json`. Its `id`s are catalog ids that plans and sets refer to, so check that none disappeared.
- The user's `CatalogEntry`s sit on top: their own exercises, and their name, description, video link and photo for any exercise. They live in the separate Catalog store of the same iCloud container (`Store.configurations`) with their own log, so the gym store stays small. Photos are stored as JPEGs of at most 1024 px (`Photo.jpeg`).
- Show a name with `ExerciseName` (`exerciseName(_:entry:)` outside views). A custom exercise whose entry hasn't synced yet shows a placeholder.
- Photos load from the repo's GitHub raw URLs (see `CatalogExercise.imageURL`), so the picker needs internet to show them.

## Workflow

- The backlog is `todo.md`, worked through with the `/todo` skill. Each item gets its own commit, and done items are ticked `[x]` and kept.
- Commit messages use an imperative subject of about 60 characters with no scope prefix ("Add searchable exercise catalog picker"). Add a body only when the reason isn't obvious.
