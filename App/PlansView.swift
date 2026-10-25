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
                    NavigationLink(plan.name.isEmpty ? "Untitled" : plan.name) { PlanEditor(plan: plan) }
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(plan) }
                        }
                }
                .onMove { from, to in
                    var moved = plans
                    moved.move(fromOffsets: from, toOffset: to)
                    for (index, plan) in moved.enumerated() { plan.order = index }
                }
            }
            .navigationTitle("Plans")
            .toolbar {
                #if os(iOS)
                EditButton()
                #endif
                Button("Add plan", systemImage: "plus") {
                    context.insert(Plan(name: "New plan", order: (plans.last?.order ?? -1) + 1))
                }
            }
        }
    }
}

struct PlanEditor: View {
    @Environment(\.modelContext) private var context
    @Bindable var plan: Plan

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
                .onMove { from, to in
                    var moved = plan.sortedItems
                    moved.move(fromOffsets: from, toOffset: to)
                    for (index, item) in moved.enumerated() { item.order = index }
                }
                Button("Add exercise", systemImage: "plus") {
                    let item = PlanItem(exercise: "", order: (plan.sortedItems.last?.order ?? -1) + 1)
                    context.insert(item)
                    item.plan = plan
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(plan.name)
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
