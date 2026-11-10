#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// Every exercise, the user's own and the bundled ones, listed like Apple Music's songs or shown as thumbnails to zoom:
/// search, sort, add to a plan, or double-click for the details. The selected one previews on the right, as in Finder.
struct ExercisesLibrary: View {
    struct Row: Identifiable {
        let id: String, name: String, muscles: String, equipment: String
    }

    struct Detail: Identifiable { let id: String }

    enum Layout: String { case list, thumbnails }

    static let thumbnailSizes = 64.0...256.0

    @Environment(\.modelContext) private var context
    @Query(sort: \CatalogEntry.name) private var entries: [CatalogEntry]
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(Action.newer) private var newer: [Action]
    @State private var search = ""
    @State private var filter = CatalogFilter()
    @State private var selection = Set<String>()
    @State private var order = [KeyPathComparator(\Row.name)]
    @State private var detail: Detail?
    @State private var previewing = false
    /// The exercises to merge, while the merge waits to be confirmed.
    @State private var merging: Set<String>?
    @AppStorage("exercisesLayout") private var layout = Layout.list
    @AppStorage("thumbnailSize") private var thumbnailSize = 128.0
    @FocusState private var tableFocused: Bool

    var body: some View {
        let own = entries.filter { filter.isEmpty && $0.isOwnExercise && (search.isEmpty || matchesEveryWord(of: search, in: [$0.name])) }
            .map { Row(id: $0.id, name: $0.name, muscles: "", equipment: "") }
        let bundled = CatalogExercise.all.filter { filter.admits($0) && (search.isEmpty || $0.matches(search)) }
            .map { Row(id: $0.id, name: $0.label, muscles: $0.primaryMuscles.map(catalogTerm).joined(separator: ", "), equipment: $0.equipment.map(catalogTerm) ?? "") }
        let rows = own + bundled
        NavigationStack { // puts the preview under the toolbar, which then spans the table and the preview in one color
            Group {
                switch layout {
                case .list: table(rows.sorted(using: order))
                case .thumbnails:
                    ExerciseGrid(rows: rows.sorted(using: order), selection: $selection, size: $thumbnailSize,
                                 open: { detail = Detail(id: $0) }, actions: actions)
                }
            }
            .searchable(text: $search, prompt: "Exercise, muscle or equipment")
            .toolbar {
                if layout == .thumbnails {
                    Slider(value: $thumbnailSize, in: Self.thumbnailSizes) {
                        Text("Size")
                    } minimumValueLabel: {
                        Image(systemName: "photo").imageScale(.small)
                    } maximumValueLabel: {
                        Image(systemName: "photo").imageScale(.large)
                    }
                    .frame(width: 140)
                }
                Picker("View", selection: $layout) {
                    Label("List", systemImage: "list.bullet").tag(Layout.list)
                    Label("Thumbnails", systemImage: "square.grid.2x2").tag(Layout.thumbnails)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                FilterMenu(filter: $filter)
                Button("Preview", systemImage: "sidebar.trailing") { previewing.toggle() }
            }
            // Solid: narrower than the toolbar's search field, the preview runs up behind a see-through toolbar.
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
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
            .alert(merging.flatMap(mergeTarget).map { String(localized: "Merge into “\(context.exerciseName($0))”?") } ?? "",
                   isPresented: Binding { merging != nil } set: { if !$0 { merging = nil } }, presenting: merging) { ids in
                Button("Merge") { perform(ids) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The others' sets and places in plans move to it. This can't be undone.")
            }
            .navigationTitle("Exercises")
            // Opened by selecting, not with the page.
            .onChange(of: selection.isEmpty) { _, empty in if !empty { previewing = true } }
            // Opening or closing the preview takes the table's focus, and with it the arrow keys; take it back once it's laid out.
            .onChange(of: previewing) { Task { tableFocused = true } }
        }
    }

    private func table(_ rows: [Row]) -> some View {
        Table(rows, selection: $selection, sortOrder: $order) {
            TableColumn("Exercise", value: \.name) { row in
                HStack {
                    ExerciseThumbnail(id: row.id, size: 28)
                    Text(row.name)
                }
            }
            TableColumn("Muscles", value: \.muscles)
            TableColumn("Equipment", value: \.equipment)
        }
        .focused($tableFocused)
        .contextMenu(forSelectionType: String.self) { actions($0) } primaryAction: { ids in
            detail = ids.first.map(Detail.init)
        }
    }

    /// What a right-click offers for the exercises it's on, in the list and as thumbnails.
    @ViewBuilder private func actions(_ ids: Set<String>) -> some View {
        Menu("Add to Plan") {
            ForEach(plans) { plan in
                Button(plan.title) { for id in ids { context.addNew(id, to: plan) } }
            }
        }
        .disabled(ids.isEmpty || plans.isEmpty || !newer.isEmpty)
        Button("Details") { detail = ids.first.map(Detail.init) }.disabled(ids.count != 1)
        Button("Merge") { merging = ids }.disabled(ids.count < 2 || !newer.isEmpty)
    }

    /// Merges `ids` into the one they keep (`mergeTarget`): plans and the catalog here, where the views see it at once, and
    /// the sets, maybe hundreds, off the main actor.
    private func perform(_ ids: Set<String>) {
        guard let target = mergeTarget(ids) else { return }
        let (container, others) = (context.container, ids.subtracting([target]))
        for id in others { context.merge(id, into: target) }
        selection = [target]
        Task.detached {
            let context = ModelContext(container)
            for id in others { context.mergeSets(id, into: target) }
            try? context.save()
        }
    }
}
#endif
