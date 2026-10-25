# Muscle Grail

Offline-first gym tracker. iPhone and Apple Watch log sets, a Mac app edits plans, and SwiftData syncs everything through the CloudKit private database. The gym has no internet, so every user action works offline.

Read [PLAN.md](PLAN.md) before changing sync, the data model, or HealthKit. It holds the decisions, known risks, and the acceptance tests that define "done".

## Build and test

- `xcode-select` points at the Command Line Tools, so prefix every `swift` / `xcodebuild` call with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Core tests: `cd Core && swift test`.
- Compile check, no signing: `xcodebuild -project MuscleGrail.xcodeproj -scheme MuscleGrail -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`. This also builds the embedded watch app and complication. Use `-destination 'platform=macOS'` for the Mac app.
- An unsigned build traps inside CloudKit at launch. To launch in the simulator, sign ad hoc: `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`. Real sync needs signed device builds (team `3Z7QAPFM7G`).

## Project shape

- The Xcode project uses synchronized folders. Add a file by creating it in `App/`, `Watch/` or `Complication/`; it joins that target automatically. Edit `project.pbxproj` only for targets, build settings or capabilities.
- `App/` is one multiplatform target (iOS + macOS). Gate platform-specific code with `#if os(iOS)` / `#if os(macOS)`.
- Code used by more than one target lives in the `Core` package: models, `Store` + `SyncMonitor`, `Health`, shared SwiftUI views, the exercise catalog.
- Concurrency: app targets use Swift 5 mode with default actor isolation `MainActor`. `Core` uses Swift 6 strict concurrency and is nonisolated by default.
- `Config/` holds entitlements and Info.plists and belongs to no target.

## Data model (CloudKit rules)

- Every property has a default or is optional, and every relationship is optional with an inverse. No `@Attribute(.unique)`. Ordering lives in an `order: Int` field. A model that breaks a rule fails the store at launch.
- Schema changes are additive: add fields, keep existing names. Renames and deletes break sync once the schema is deployed to Production.
- An exercise is its name string (`PlanItem.exercise`, `LoggedSet.exercise`). History and prefill match on that name.
- `LoggedSet` is append-only: one record per set, deleted to undo.
- `ModelContext.log` saves immediately, because the watch app can be killed between sets.

## Sync and HealthKit

- SwiftData has no "sync now" API. Background wakes come from CloudKit silent pushes and the HealthKit step observer (`Health.observeSteps`). The observer must be registered at every launch, background launches included. `SyncMonitor.waitUntilIdle()` holds a wake open until sync settles.
- A workout goes to HealthKit only from the device that ran it. That device stores the UUID in `Workout.healthKitID`.
- The CloudKit container `iCloud.de.grails.musclegrail` is permanent: Apple can't delete or rename it.

## Exercise catalog

- `Core/Sources/Core/exercises.json` is [free-exercise-db](https://github.com/yuhonas/free-exercise-db), public domain, bundled unchanged. To update it, replace the file with that repo's `dist/exercises.json`.
- Photos load from the repo's GitHub raw URLs (see `CatalogExercise.imageURL`), so the picker needs internet to show them.
