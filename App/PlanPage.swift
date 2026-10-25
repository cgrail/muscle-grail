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
    @State private var selection: UUID? // lets the arrow keys move between the exercises

    var body: some View {
        let locked = !newer.isEmpty
        let items = plan.sortedItems.filter { search.isEmpty || context.exerciseName($0.exerciseID).localizedCaseInsensitiveContains(search) }
        List(selection: $selection) {
            if locked { UpdateToEdit() }
            HStack(alignment: .bottom, spacing: 20) {
                PlanArtwork(plan: plan, size: 140).shadow(radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Name", text: Binding { plan.name } set: { context.rename(plan, to: $0) })
                        .font(.largeTitle.bold())
                        .textFieldStyle(.plain)
                    if let focus = plan.focus {
                        Text(verbatim: focus).font(.title3).foregroundStyle(.tint)
                    }
                    Text("\(plan.sortedItems.count) exercises").foregroundStyle(.secondary)
                    PlanAssistant(plan: plan)
                }
            }
            .disabled(locked)
            .padding(.vertical, 12)
            .listRowSeparator(.hidden)
            Section {
                ForEach(items) { PlanRow(item: $0).disabled(locked).tag($0.id) }
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
            count("Sets", item.targetSets, in: 1...20) { context.setTargets(item, sets: $0) }
                .frame(width: Column.sets, alignment: .leading)
            count("Reps", item.targetReps, in: 1...100) { context.setTargets(item, reps: $0) }
                .frame(width: Column.reps, alignment: .leading)
            Stepper {
                WeightField(kg: Binding { item.targetWeightKg } set: { context.setTargets(item, weightKg: $0) })
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

    /// A number to type, or to step to. A typed one outside `range` lands on its nearest end.
    private func count(_ title: LocalizedStringKey, _ value: Int, in range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        let binding = Binding { value } set: { set(min(max($0, range.lowerBound), range.upperBound)) }
        return Stepper(value: binding, in: range) {
            TextField(title, value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 44)
        }
    }
}
#endif
