import Core
import SwiftData
import SwiftUI

/// Searchable exercise catalog: the user's own exercises, then the bundled ones. Search text can become a new exercise.
struct ExercisePicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CatalogEntry.name) private var entries: [CatalogEntry]
    @State private var search = ""
    @State private var region: BodyRegion?
    let onPick: (String) -> Void

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        // the user's own exercises have no muscles, so a region hides them
        let custom = entries.filter { region == nil && CatalogExercise.byID[$0.id] == nil && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
        let results = CatalogExercise.all.filter { $0.trains(region) && (query.isEmpty || $0.matches(query)) }
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
                    Button { pick(exercise.id) } label: { CatalogRow(name: exercise.name, detail: exercise.detail, imageURL: exercise.imageURL) }
                        .buttonStyle(.plain)
                }
            }
            .searchable(text: $search, prompt: "Exercise, muscle or equipment")
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem { RegionFilter(region: $region) }
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

/// Shows only the exercises for one body region, like legs or arms.
struct RegionFilter: View {
    @Binding var region: BodyRegion?

    var body: some View {
        Picker("Body region", systemImage: region == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill", selection: $region) {
            Text("All exercises").tag(BodyRegion?.none)
            ForEach(BodyRegion.allCases, id: \.self) { Text($0.name).tag(Optional($0)) }
        }
        .pickerStyle(.menu)
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
