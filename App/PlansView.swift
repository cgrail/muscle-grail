import Core
import SwiftData
import SwiftUI

#if os(iOS)
/// Training's edit mode on the iPhone: every plan in its order, to drag into another, delete, share, or open to edit.
/// A new plan opens to edit. Changes lists what changed across all plans. `onDone` goes back to training.
struct PlansView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Action.newer) private var newer: [Action]
    let onDone: () -> Void
    @State private var opened: Plan?

    var body: some View {
        let locked = !newer.isEmpty
        List {
            if locked { UpdateToEdit() }
            ForEach(plans) { plan in
                Button { opened = plan } label: { // a plain button: in edit mode a list row takes no taps
                    HStack {
                        PlanLabel(plan, among: plans)
                        Spacer()
                        SharedBadge(plan: plan)
                        PlanSyncBadge(plan: plan)
                        Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    PlanSharing(plan: plan)
                    Button("Delete", systemImage: "trash", role: .destructive) { context.deletePlan(plan) }.disabled(locked)
                }
            }
            .onMove { context.reorder(plans, fromOffsets: $0, toOffset: $1) }
            .onDelete { offsets in offsets.map { plans[$0] }.forEach { context.deletePlan($0) } }
            .moveDisabled(locked)
            .deleteDisabled(locked)
        }
        .environment(\.editMode, .constant(.active)) // on the list only, so an opened plan isn't in edit mode
        .navigationTitle("Plans")
        .toolbar {
            NavigationLink { PlanChanges() } label: { Label("Changes", systemImage: "clock.arrow.circlepath") }
            Button("Add plan", systemImage: "plus") { opened = context.addPlan() }.disabled(locked)
            SettingsButton()
            Button("Done", action: onDone)
        }
        .navigationDestination(item: $opened) { PlanEditor(plan: $0) }
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
