import Core
import SwiftData
import SwiftUI

struct PlansView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]

    var body: some View {
        NavigationStack {
            List {
                ForEach(plans) { plan in
                    NavigationLink(plan.title) { PlanEditor(plan: plan) }
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(plan) }
                        }
                }
                .onMove { plans.reorder(fromOffsets: $0, toOffset: $1) }
            }
            .navigationTitle("Plans")
            .toolbar {
                #if os(iOS)
                EditButton()
                #endif
                Button("Add plan", systemImage: "plus") { context.addPlan() }
            }
        }
    }
}

struct PlanEditor: View {
    @Environment(\.modelContext) private var context
    @Bindable var plan: Plan
    @State private var picking = false

    var body: some View {
        Form {
            TextField("Name", text: $plan.name)
            Section("Exercises") {
                ForEach(plan.sortedItems) { item in
                    PlanItemRow(item: item)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(item) }
                        }
                }
                .onMove { plan.sortedItems.reorder(fromOffsets: $0, toOffset: $1) }
                Button("Add exercise", systemImage: "plus") { picking = true }
            }
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
    @Bindable var item: PlanItem

    var body: some View {
        #if os(macOS)
        let layout = AnyLayout(HStackLayout())
        #else
        let layout = AnyLayout(VStackLayout(alignment: .leading))
        #endif
        layout {
            TextField("Exercise", text: $item.exercise)
            Stepper("\(item.targetSets) sets", value: $item.targetSets, in: 1...20)
            Stepper("\(item.targetReps) reps", value: $item.targetReps, in: 1...100)
            Stepper("\(item.targetWeightKg.formatted()) kg", value: $item.targetWeightKg, in: 0...1000, step: 2.5)
        }
    }
}
