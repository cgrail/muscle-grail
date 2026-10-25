#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// A plan as Apple Music shows a playlist: artwork and name on top, then its exercises as a table to edit in place.
struct PlanPage: View {
    @Environment(\.modelContext) private var context
    @Query(Action.newer) private var newer: [Action]
    let plan: Plan
    @State private var search = ""
    @State private var picking = false

    var body: some View {
        let locked = !newer.isEmpty
        let items = plan.sortedItems.filter { search.isEmpty || context.exerciseName($0.exerciseID).localizedCaseInsensitiveContains(search) }
        List {
            if locked { UpdateToEdit() }
            HStack(alignment: .bottom, spacing: 20) {
                PlanArtwork(plan: plan, size: 140).shadow(radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Name", text: Binding { plan.name } set: { context.rename(plan, to: $0) })
                        .font(.largeTitle.bold())
                        .textFieldStyle(.plain)
                    Text("\(plan.sortedItems.count) exercises").foregroundStyle(.secondary)
                    PlanAssistant(plan: plan)
                }
            }
            .disabled(locked)
            .padding(.vertical, 12)
            .listRowSeparator(.hidden)
            Section {
                ForEach(items) { PlanRow(item: $0).disabled(locked) }
                    .onMove { context.reorder(plan.sortedItems, fromOffsets: $0, toOffset: $1) }
                    .moveDisabled(locked || !search.isEmpty) // offsets count the filtered rows
            } header: {
                HStack {
                    Text("Exercise")
                    Spacer()
                    Text("Sets").frame(width: Column.sets, alignment: .leading)
                    Text("Reps").frame(width: Column.reps, alignment: .leading)
                    Text("Weight").frame(width: Column.weight, alignment: .leading)
                    Color.clear.frame(width: Column.menu)
                }
            }
        }
        .listStyle(.inset)
        .searchable(text: $search, prompt: "Find in Plan")
        .toolbar {
            Button("Add exercise", systemImage: "plus") { picking = true }.disabled(locked)
        }
        .sheet(isPresented: $picking) { ExercisePicker { context.add($0, to: plan) } }
        .navigationTitle(plan.title)
    }
}

private enum Column {
    static let sets = 90.0, reps = 90.0, weight = 120.0, menu = 28.0
}

private struct PlanRow: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    @State private var showingDetail = false

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(id: item.exerciseID, size: 36)
            VStack(alignment: .leading) {
                ExerciseName(item.exerciseID)
                Text(verbatim: CatalogExercise.byID[item.exerciseID]?.detail ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(value: Binding { item.targetSets } set: { context.setTargets(item, sets: $0) }, in: 1...20) {
                Text(item.targetSets.formatted()).monospacedDigit()
            }
            .frame(width: Column.sets, alignment: .leading)
            Stepper(value: Binding { item.targetReps } set: { context.setTargets(item, reps: $0) }, in: 1...100) {
                Text(item.targetReps.formatted()).monospacedDigit()
            }
            .frame(width: Column.reps, alignment: .leading)
            Stepper {
                Text(verbatim: "\(item.targetWeightKg.formatted()) kg").monospacedDigit()
            } onIncrement: {
                context.setTargets(item, weightKg: Weights.next(after: item.targetWeightKg, for: item.exerciseID))
            } onDecrement: {
                context.setTargets(item, weightKg: Weights.previous(before: item.targetWeightKg, for: item.exerciseID))
            }
            .frame(width: Column.weight, alignment: .leading)
            Menu {
                Button("Details", systemImage: "info.circle") { showingDetail = true }
                Button("Delete", systemImage: "trash", role: .destructive) { context.deleteExercise(item) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: Column.menu)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingDetail) { ExerciseDetail(id: item.exerciseID) }
    }
}
#endif
