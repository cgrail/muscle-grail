---
name: todo
description: Work the next item(s) off todo.md in this repo, one item at a time, checked headlessly, with one commit per finished item. Use when asked to "work on the todos", "do the next todo" or "keep going through todo.md", or when handed a todo item by name.
allowed-tools: Read, Edit, Write, Grep, Glob, Bash
---

## The list

!`cat todo.md`

`todo.md` at the repo root is the backlog. `[ ]` is open and `[x]` is done. Done items stay in the file as a record; they are not deleted.

Arguments, if any, name which item(s) to take (a number, a keyword, "all"). With no arguments, take the **topmost `[ ]` item** and keep going down the list until the context or usage limit stops you. If a later item is a prerequisite for an earlier one, do it first and say so in its commit body.

## One item = one commit

Do **not** batch items. For each item, in order:

1. **Read the item as a bug report, not a spec.** Most entries are one line of the user's shorthand ("the watch forgot my last set"). Find the actual code before deciding what the fix is: the symptom is usually a small piece of a shared code path in `Core`.
2. **Locate it.** [CLAUDE.md](../../../CLAUDE.md) maps the folders. A change usually touches more than one layer, so follow a feature through every layer it touches:
   - **Core** (`Core/Sources/Core/`): the models in `Models.swift`, plan editing in `Plans.swift`, the workout flow and prefill in `Training.swift`, `Store` and `SyncMonitor` in `Store.swift`, HealthKit in `Health.swift`, the views the iPhone, Mac and watch share in `Views.swift`, the action logs in `Actions.swift`, the bundled catalog in `Catalog.swift` and the user's own catalog data in `Exercises.swift`, Claude's MCP tools and server in `MCP.swift` and `MCPServer.swift`, statistics in `Stats.swift`, weight steps in `Weights.swift`.
   - **iPhone and Mac** (`App/`, one target): `PlansView`, `ExercisePicker`, `ExerciseDetail`, `TrainView`, `HistoryView` with `ActivitySection` (its `ActivityGrid`, and `Goals` on iOS) and `StatsSection`, `MuscleGrailApp`; Mac only: `PlanAssistant`, `ClaudeSettings`.
   - **Watch** (`Watch/`): `WatchWorkoutView` with its `WorkoutSession`, and `MuscleGrailWatchApp`. **Complication and iPhone widget** (`Complication/`, built as `StepsComplication` and `StepsWidget`): `StepsComplication.swift`.
   - **Strings:** each target's `Localizable.xcstrings` and `InfoPlist.xcstrings`; Core's catalog is in `Core/Sources/Core/`.
3. **Implement.** Match the surrounding code's idiom: terse, comments only for the why. Logic goes in `Core`, where the tests reach it; views only call it.
4. **Check the constraints in CLAUDE.md** that the change touches. The ones that bite most often:
   - **Offline:** every action works with no network, and nothing a user does waits on sync.
   - **Platform roles:** plans are created and maintained on the Mac; the watch logs, adds and deletes sets and edits nothing else.
   - **Actions:** every model change goes through `record` as a `Change`; a new case or field bumps `Change.version`. Training never checks a version.
   - **Model migrations:** an item that needs a model or field added to the schema stops here: describe the change and ask the user for approval before making it.
   - **CloudKit rules:** every new property has a default or is optional, every relationship is optional with an inverse, and the schema only grows (no renames, no deletes).
   - **Strings:** every new user-facing string has German in its catalog, and Core's strings name `bundle: .module`.
   - **Saved data:** `UserDefaults` keys keep their names and meaning.
   - **File size:** files stay under 300 lines. If a change pushes one past that, split it along a feature seam as part of the item.
5. **Verify what can be verified from here.** Put `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in front of each:
   ```bash
   cd Core && swift test --enable-code-coverage   # then the llvm-cov report in CLAUDE.md: every file at 90%+
   xcodebuild -project MuscleGrail.xcodeproj -scheme MuscleGrail -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build   # iPhone, watch and complication
   xcodebuild -project MuscleGrail.xcodeproj -scheme MuscleGrail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
   ```
   When the item adds or changes a behavior, add or change **one** test that fails without it; the integration tests stay at 10 (CLAUDE.md, Tests). New strings get synced into their catalog and translated (CLAUDE.md, Localization). The user judges how it looks and feels on the iPhone, Watch and Mac, and CloudKit only syncs in signed device builds, so a sync change ends with the acceptance tests from PLAN.md it touches, for the user to run.
6. **The changelog, and docs if something significant changed.**
   - Anything a user would notice: an entry in [CHANGELOG.md](../../../CHANGELOG.md) under the current version.
   - A new subsystem, a changed invariant, or a rule a future edit could break: the matching section of [CLAUDE.md](../../../CLAUDE.md).
   - A changed decision about sync, the data model or HealthKit: [PLAN.md](../../../PLAN.md).
   - A bug fix that changes no rule: none of them.
7. **Tick the item** in `todo.md`: `[ ]` → `[x]`. If the work revealed a follow-up the user should decide on, append it as a new `[ ]` line rather than doing it silently.
8. **Commit everything for that item together:** code, tests, catalogs, `todo.md`, the changelog and docs, with a message in the style of CLAUDE.md's Workflow section. **Then push it straight to `main`**, without asking, only with every check green. If the push is rejected because `main` moved, rebase onto `origin/main`, resolve any conflicts keeping both sides' intent, run the checks again and push. Never force-push.

## Reporting

After each commit, tell the user in two or three lines:
- what the item turned out to be
- what changed
- **what to check by hand**: how it looks and feels on the iPhone, Watch and Mac, and any acceptance test from PLAN.md it touches

Then start the next item without asking. Stop only when the list is empty, when an item needs a decision only the user can make, or when you run out of room.
