import Core
import SwiftData
import SwiftUI

/// Searchable exercise catalog: the user's own exercises, then the bundled ones. Search text can become a new exercise.
struct ExercisePicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CatalogEntry.name) private var entries: [CatalogEntry]
    @State private var search = ""
    @State private var filter = CatalogFilter()
    let onPick: (String) -> Void

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let custom = entries.filter { filter.isEmpty && CatalogExercise.byID[$0.id] == nil && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
        let results = CatalogExercise.alphabetical.filter { filter.admits($0) && (query.isEmpty || $0.matches(query)) }
        NavigationStack {
            List {
                if !query.isEmpty {
                    Button("Add “\(query)”", systemImage: "plus") { pick(context.createExercise(named: query)) }
                }
                ForEach(custom) { entry in
                    Button { pick(entry.id) } label: { CatalogRow(name: entry.name, detail: entry.details, photo: entry.photo) }
                        .buttonStyle(.plain)
                }
                ForEach(results) { exercise in
                    Button { pick(exercise.id) } label: { CatalogRow(name: exercise.label, detail: exercise.detail, imageURL: exercise.imageURL) }
                        .buttonStyle(.plain)
                }
            }
            .searchable(text: $search, prompt: "Exercise, muscle or equipment")
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem { FilterMenu(filter: $filter) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    private func pick(_ id: String) {
        onPick(id)
        dismiss()
    }
}

/// Shows only the exercises for a body region, level, piece of equipment and category, like legs for beginners with dumbbells.
struct FilterMenu: View {
    @Binding var filter: CatalogFilter

    var body: some View {
        Menu("Filter", systemImage: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") {
            Picker("Body region", selection: $filter.region) {
                Text("All").tag(BodyRegion?.none)
                ForEach(BodyRegion.allCases, id: \.self) { Text($0.name).tag(Optional($0)) }
            }
            picker("Level", $filter.level, CatalogFilter.levels)
            picker("Equipment", $filter.equipment, CatalogFilter.equipment)
            picker("Category", $filter.category, CatalogFilter.categories)
            if !filter.isEmpty {
                Button("Show all exercises") { filter = CatalogFilter() }
            }
        }
    }

    private func picker(_ title: LocalizedStringKey, _ selection: Binding<String?>, _ terms: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("All").tag(String?.none)
            ForEach(terms, id: \.self) { Text(catalogTerm($0)).tag(Optional($0)) }
        }
    }
}

private struct CatalogRow: View {
    let name: String
    let detail: String
    var photo: Data?
    var imageURL: URL?

    var body: some View {
        HStack {
            Group {
                if let image = photo.flatMap(Photo.image) {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.2)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}
