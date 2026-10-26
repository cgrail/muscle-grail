# Todo

- [ ] add import/export mechanism from gymbook
- [ ] move an exercise to another plan in one step: a `moveExercise` change (`Change.version` 2) that keeps its sets, reps and weight, as "Move to" in an exercise's menu on the Mac and the iPhone. Plan sharing needs it to send a move as one change
- [ ] plan sharing, the rules in Core (see PLAN.md, Sharing plans with a training partner): which changes go to the partner (structure of shared plans, never targets or the plan list's order) and how a received one applies (only the partner's, oldest first, through `record`, never sent back; a change to a missing plan or exercise changes nothing; reorder keeps this side's own exercises after the one they followed; a new plan goes to the end of the list; a new exercise takes the sender's sets and reps and this person's last weight; a custom exercise brings its name). Replace the least important integration test with "a structure change reaches the partner, their weights stay"
- [ ] plan sharing, sync: `CKSyncEngine` for the `Partner` zone on the iPhone and the Mac (the owner's on the private database, scoped to the zone; the partner's on the shared database), with `SharedPlan`, `SharedChange` and `PartnerSettings` records, its state and the zone cache saved in a file on the device, fetched on silent pushes and the HealthKit step wake, all off the main actor. A thin wrapper like `Health.swift`
- [ ] plan sharing, one invite: Settings → Training partner on the Mac and the iPhone, all plans (default) or chosen plans, one zone-wide `CKShare` through the share sheet, stop sharing or leave. "Share with <partner>" and "Stop sharing" in a plan's menu, and a badge on shared plans. `CKSharingSupported` in the Info.plists
- [ ] plan sharing, accept the invite on the iPhone and the Mac (`userDidAcceptCloudKitShareWith`) and add every shared plan with its ids, at the end of the plan list
- [ ] plan sharing, ask "Only me / Me and <partner>" on structure changes to a shared plan, in the Mac's plan page and sidebar and the iPhone's plans; a rename asks once, when the name is done. Settings → Training partner: "Ask each time" (default) or "Always both", in iCloud's key-value store; add its key to CLAUDE.md's saved data
- [ ] plan sharing, Claude: an optional `shared` argument for `create_plan` and `add_exercises`; without it they follow "Always both", else they change only your plans
- [x] add backup mechanism to folder on mac with auto write on save/load/edit
- [x] add filter for level, equipment and category
- [x] show instructions
- [x] enable keyboard up/down navigation on mac
- [x] enable direct entry of reps/sets on mac via number
- [x] add translation for excercise to german - name 
- [x] restore from the Mac's backup folder: merge the backup's actions into the store, or replace the store with it? replace
- [x] add github actions for pr and main build
- [x] also include https://github.com/RepDB/exercise-dataset with correct attribution -  https://github.com/RepDB/exercise-dataset/blob/main/ATTRIBUTION.md