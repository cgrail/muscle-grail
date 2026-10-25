#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// Every exercise, the user's own and the bundled ones, listed like Apple Music's songs: search, sort, add to a plan,
/// or double-click for the details. The selected one previews on the right, as in Finder.
struct ExercisesLibrary: View {
    struct Row: Identifiable {
        let id: String, name: String, muscles: String, equipment: String
    }

    struct Detail: Identifiable { let id: String }

    @Environment(\.modelContext) private var context
    @Query(sort: \CatalogEntry.name) private var entries: [CatalogEntry]
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Action.newer) private var newer: [Action]
    @State private var search = ""
    @State private var filter = CatalogFilter()
    @State private var selection = Set<String>()
    @State private var order = [KeyPathComparator(\Row.name)]
    @State private var detail: Detail?
    @State private var previewing = true

    var body: some View {
        let own = entries.filter { filter.isEmpty && CatalogExercise.byID[$0.id] == nil }.map { Row(id: $0.id, name: $0.name, muscles: "", equipment: "") }
        let bundled = CatalogExercise.all.filter(filter.admits).map { Row(id: $0.id, name: $0.label, muscles: $0.primaryMuscles.map(catalogTerm).joined(separator: ", "), equipment: $0.equipment.map(catalogTerm) ?? "") }
        let rows = (own + bundled).filter { search.isEmpty || matchesEveryWord(of: search, in: [$0.name, $0.muscles, $0.equipment]) }
        Table(rows.sorted(using: order), selection: $selection, sortOrder: $order) {
            TableColumn("Exercise", value: \.name) { row in
                HStack {
                    ExerciseThumbnail(id: row.id, size: 28)
                    Text(row.name)
                }
            }
            TableColumn("Muscles", value: \.muscles)
            TableColumn("Equipment", value: \.equipment)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Menu("Add to Plan") {
                ForEach(plans) { plan in
                    Button(plan.title) { for id in ids { context.add(id, to: plan) } }
                }
            }
            .disabled(ids.isEmpty || plans.isEmpty || !newer.isEmpty)
            Button("Details") { detail = ids.first.map(Detail.init) }.disabled(ids.count != 1)
        } primaryAction: { ids in
            detail = ids.first.map(Detail.init)
        }
        .searchable(text: $search, prompt: "Exercise, muscle or equipment")
        .toolbar {
            FilterMenu(filter: $filter)
            Button("Preview", systemImage: "sidebar.trailing") { previewing.toggle() }
        }
        .inspector(isPresented: $previewing) {
            Group {
                if selection.count == 1, let id = selection.first {
                    ExercisePreview(id: id)
                } else {
                    ContentUnavailableView("Select an exercise", systemImage: "dumbbell")
                }
            }
            .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
        }
        .sheet(item: $detail) { ExerciseDetail(id: $0.id) }
        .navigationTitle("Exercises")
    }
}
#endif
