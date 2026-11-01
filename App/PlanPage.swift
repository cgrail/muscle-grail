#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// A plan as Apple Music shows a playlist: artwork and name on top, then its exercises as a table to edit in place.
/// The selected exercise previews on the right, like in the exercise library.
struct PlanPage: View {
    enum Inspector { case preview, changes }

    @Environment(\.modelContext) private var context
    @Query(Action.newer) private var newer: [Action]
    let plan: Plan
    @State private var search = ""
    @State private var picking = false
    @State private var selection: UUID? // lets the arrow keys move between the exercises
    @State private var inspecting = false
    @State private var inspector = Inspector.preview // kept while it closes, so it doesn't change as it slides out
    @FocusState private var listFocused: Bool
    @State private var forWhom: PendingEdit?

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
                ForEach(items) { PlanRow(item: $0, forWhom: $forWhom).disabled(locked || $0.ownedBy == .partner).tag($0.id) }
                    .onMove { context.reorder(plan.sortedItems, fromOffsets: $0, toOffset: $1) }
                    .moveDisabled(locked || !search.isEmpty) // offsets count the filtered rows
            } header: {
                HStack {
                    Text("Exercise")
                    Spacer()
                    Color.clear.frame(width: Column.owner)
                    HStack(spacing: 4) {
                        Text("Sets")
                        Text(verbatim: "×")
                        Text("Reps")
                    }
                    .frame(width: Column.targets, alignment: .leading)
                    Text("Weight").frame(width: Column.weight, alignment: .leading)
                    Color.clear.frame(width: Column.menu)
                }
            }
        }
        .listStyle(.inset)
        .focused($listFocused)
        .searchable(text: $search, prompt: "Find in Plan")
        .toolbar {
            Button("Add exercise", systemImage: "plus") { picking = true }.disabled(locked)
            Button("Changes", systemImage: "clock.arrow.circlepath") { toggle(.changes) }
            Button("Preview", systemImage: "sidebar.trailing") { toggle(.preview) }
        }
        .inspector(isPresented: $inspecting) {
            switch inspector {
            case .changes: PlanChanges(plan: plan.id)
            case .preview:
                Group {
                    if let item = plan.sortedItems.first(where: { $0.id == selection }) {
                        ExercisePreview(id: item.exerciseID)
                    } else {
                        ContentUnavailableView("Select an exercise", systemImage: "dumbbell")
                    }
                }
                .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
            }
        }
        // Opened by selecting, unless the changes are open.
        .onChange(of: selection == nil) { _, none in if !none && !inspecting { toggle(.preview) } }
        // Opening or closing the inspector takes the list's focus, and with it the arrow keys; take it back once it's laid out.
        .onChange(of: inspecting) { Task { listFocused = true } }
        .sheet(isPresented: $picking) {
            ExercisePicker { id in ForWhom.edit(plan, asking: $forWhom) { context.addNew(id, to: plan, own: $0 ? nil : .mine) } }
        }
        .forWhom($forWhom)
        .navigationTitle(plan.title)
    }

    /// Shows `kind` in the inspector, or closes the inspector if it already shows it.
    private func toggle(_ kind: Inspector) {
        inspecting = !inspecting || inspector != kind
        inspector = kind
    }
}

private enum Column {
    static let owner = 28.0, targets = 100.0, weight = 120.0, menu = 28.0
}

private struct PlanRow: View {
    @Environment(\.modelContext) private var context
    let item: PlanItem
    @Binding var forWhom: PendingEdit?
    @State private var showingDetail = false
    @State private var replacing = false

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(id: item.exerciseID, size: 36)
            VStack(alignment: .leading) {
                ExerciseName(item.exerciseID)
                Text(verbatim: CatalogExercise.byID[item.exerciseID]?.detail ?? "").font(.caption).foregroundStyle(.secondary)
                if item.ownedBy == .partner { OwnerNote(item: item) }
            }
            Spacer()
            OwnerButton(item: item).frame(width: Column.owner)
            TargetsButton(item: item).frame(width: Column.targets, alignment: .leading)
            if item.showsWeight {
                WeightStepper(kg: Binding { item.targetWeightKg } set: { context.setTargets(item, weightKg: $0) }, exerciseID: item.exerciseID)
                    .frame(width: Column.weight, alignment: .leading)
            } else {
                Color.clear.frame(width: Column.weight) // a bodyweight move has no weight
            }
            Menu {
                Button("Details", systemImage: "info.circle") { showingDetail = true }
                Button("Replace with…", systemImage: "arrow.left.arrow.right") { replacing = true }
                MoveToPlan(item: item, forWhom: $forWhom)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    ForWhom.edit(item.plan, item, asking: $forWhom) { context.deleteExercise(item, forBoth: $0) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: Column.menu)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingDetail) { ExerciseDetail(id: item.exerciseID) }
        .sheet(isPresented: $replacing) {
            ExercisePicker(title: "Replace with") { id in ForWhom.edit(item.plan, item, asking: $forWhom) { context.replace(item, with: id, forBoth: $0) } }
        }
    }
}
#endif
