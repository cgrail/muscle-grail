import Core
import SwiftData
import SwiftUI

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
                            Text(plan.title)
                            Spacer()
                            SharedBadge(plan: plan)
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
                #if os(iOS)
                EditButton()
                #endif
                NavigationLink { PlanChanges() } label: { Label("Changes", systemImage: "clock.arrow.circlepath") }
                Button("Add plan", systemImage: "plus") { context.addPlan() }.disabled(locked)
            }
        }
    }
}

struct PlanEditor: View {
    @Environment(\.modelContext) private var context
    @Query(Action.newer) private var newer: [Action]
    let plan: Plan
    @State private var picking = false
    @State private var replacing: PlanItem?
    @State private var forWhom: PendingEdit?

    var body: some View {
        Form {
            if !newer.isEmpty { UpdateToEdit() }
            Group {
                TextField("Name", text: Binding { plan.name } set: { context.rename(plan, to: $0) })
                Section("Exercises") {
                    ForEach(plan.sortedItems) { item in
                        PlanItemRow(item: item)
                            .contextMenu {
                                Button("Replace with…", systemImage: "arrow.left.arrow.right") { replacing = item }
                                MoveToPlan(item: item, forWhom: $forWhom)
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    ForWhom.edit(plan, item, asking: $forWhom) { context.deleteExercise(item, forBoth: $0) }
                                }
                            }
                            .disabled(item.ownedBy == .partner)
                    }
                    .onMove { context.reorder(plan.sortedItems, fromOffsets: $0, toOffset: $1) }
                    Button("Add exercise", systemImage: "plus") { picking = true }
                }
            }
            .disabled(!newer.isEmpty)
        }
        .formStyle(.grouped)
        .navigationTitle(plan.title)
        .sheet(isPresented: $picking) {
            ExercisePicker { id in ForWhom.edit(plan, asking: $forWhom) { context.add(id, to: plan, own: $0 ? nil : .mine) } }
        }
        .sheet(item: $replacing) { item in
            ExercisePicker(title: "Replace with") { id in ForWhom.edit(plan, item, asking: $forWhom) { context.replace(item, with: id, forBoth: $0) } }
        }
        .forWhom($forWhom)
        #if os(iOS)
        .toolbar {
            EditButton()
            NavigationLink { PlanChanges(plan: plan.id) } label: { Label("Changes", systemImage: "clock.arrow.circlepath") }
        }
        #endif
    }
}

private struct PlanItemRow: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    @State private var showingDetail = false

    var body: some View {
        VStack(alignment: .leading) {
            OwnerNote(item: item)
            HStack {
                ExerciseName(item.exerciseID)
                Button("Details", systemImage: "info.circle") { showingDetail = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Stepper("\(item.targetSets) sets", value: Binding { item.targetSets } set: { context.setTargets(item, sets: $0) }, in: 1...20)
            Stepper("\(item.targetReps) reps", value: Binding { item.targetReps } set: { context.setTargets(item, reps: $0) }, in: 1...100)
            WeightStepper(kg: Binding { item.targetWeightKg } set: { context.setTargets(item, weightKg: $0) }, exerciseID: item.exerciseID)
        }
        .sheet(isPresented: $showingDetail) { ExerciseDetail(id: item.exerciseID) }
    }
}

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
