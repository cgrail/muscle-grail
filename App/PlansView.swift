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
                    NavigationLink(plan.title) { PlanEditor(plan: plan) }
                        .contextMenu {
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

    var body: some View {
        Form {
            if !newer.isEmpty { UpdateToEdit() }
            Group {
                TextField("Name", text: Binding { plan.name } set: { context.rename(plan, to: $0) })
                Section("Exercises") {
                    ForEach(plan.sortedItems) { item in
                        PlanItemRow(item: item)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { context.deleteExercise(item) }
                            }
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
            ExercisePicker { context.add($0, to: plan) }
        }
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }
}

private struct PlanItemRow: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    @State private var showingDetail = false

    var body: some View {
        #if os(macOS)
        let layout = AnyLayout(HStackLayout())
        #else
        let layout = AnyLayout(VStackLayout(alignment: .leading))
        #endif
        layout {
            HStack {
                ExerciseName(item.exerciseID)
                Button("Details", systemImage: "info.circle") { showingDetail = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Stepper("\(item.targetSets) sets", value: Binding { item.targetSets } set: { context.setTargets(item, sets: $0) }, in: 1...20)
            Stepper("\(item.targetReps) reps", value: Binding { item.targetReps } set: { context.setTargets(item, reps: $0) }, in: 1...100)
            Stepper(
                "\(item.targetWeightKg.formatted()) kg",
                value: Binding { item.targetWeightKg } set: { context.setTargets(item, weightKg: $0) }, in: 0...1000, step: 2.5
            )
        }
        .sheet(isPresented: $showingDetail) { ExerciseDetail(id: item.exerciseID) }
    }
}

/// Shown while a newer app version has changed the data: plans wait for the update, training works as usual.
private struct UpdateToEdit: View {
    var body: some View {
        Label("Update Muscle Grail to edit plans. A newer version changed them. Training works as usual.", systemImage: "arrow.down.app")
            .foregroundStyle(.secondary)
    }
}
