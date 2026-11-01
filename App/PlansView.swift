import Core
import SwiftData
import SwiftUI

#if os(iOS)
struct PlansView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Action.newer) private var newer: [Action]

    var body: some View {
        let locked = !newer.isEmpty
        NavigationStack {
            List {
                if locked { UpdateToEdit() }
                ForEach(plans) { plan in
                    NavigationLink { PlanEditor(plan: plan) } label: {
                        HStack {
                            PlanLabel(plan)
                            Spacer()
                            SharedBadge(plan: plan)
                            PlanSyncBadge(plan: plan)
                        }
                    }
                    .contextMenu {
                        PlanSharing(plan: plan)
                        Button("Delete", systemImage: "trash", role: .destructive) { context.deletePlan(plan) }.disabled(locked)
                    }
                }
                .onMove { context.reorder(plans, fromOffsets: $0, toOffset: $1) }
                .moveDisabled(locked)
            }
            .navigationTitle("Plans")
            .toolbar {
                EditButton()
                NavigationLink { PlanChanges() } label: { Label("Changes", systemImage: "clock.arrow.circlepath") }
                Button("Add plan", systemImage: "plus") { context.addPlan() }.disabled(locked)
                SettingsButton()
            }
        }
    }
}
#endif

/// An exercise's "Move to" menu: every other plan, to move it to the end of, with its sets, reps and weight.
struct MoveToPlan: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    let item: PlanItem
    @Binding var forWhom: PendingEdit?

    var body: some View {
        Menu("Move to", systemImage: "arrow.turn.up.right") {
            ForEach(plans.filter { $0.id != item.plan?.id }) { plan in
                Button(plan.title) { ForWhom.edit(item.plan, item, asking: $forWhom) { context.move(item, to: plan, forBoth: $0) } }
            }
        }
    }
}

/// Shown while a newer app version has changed the data: plans wait for the update, training works as usual.
struct UpdateToEdit: View {
    var body: some View {
        Label("Update Muscle Grail to edit plans. A newer version changed them. Training works as usual.", systemImage: "arrow.down.app")
            .foregroundStyle(.secondary)
    }
}

/// The dice beside a plan's name: the next funny name for what it trains. A name it gives changes with the plan's exercises.
struct FunnyNameButton: View {
    @Environment(\.modelContext) private var context
    let plan: Plan

    var body: some View {
        Button("Funny name", systemImage: "dice") { context.rollFunnyName(plan) }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless) // only the dice, not the whole row
            .help("Funny name")
            .disabled(plan.focus == nil)
    }
}

/// Whether this device's changes to a plan have reached iCloud, from where the other devices fetch them.
struct PlanSyncBadge: View {
    let plan: Plan

    var body: some View {
        if SyncMonitor.shared.inICloud(plan) {
            Image(systemName: "checkmark.icloud").foregroundStyle(.secondary).accessibilityLabel("In iCloud").help("In iCloud")
        } else {
            Image(systemName: "icloud.and.arrow.up").foregroundStyle(.orange).accessibilityLabel("Waiting to upload").help("Waiting to upload")
        }
    }
}
