#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// Picks the exercise another app's exercise becomes: the likeliest first, then the whole catalog to search, and beside
/// them the selected one's photo, facts and steps. Arrow keys move through the list; Choose or a double-click takes one.
struct ExerciseChooser: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CatalogEntry.name) private var entries: [CatalogEntry]
    /// The other app's name for it, which a new exercise of your own keeps.
    let name: String
    let likeliest: [String]
    /// Gets nil for a new exercise of your own.
    let onChoose: (String?) -> Void
    @State private var selection: String?
    @State private var search = ""

    init(name: String, likeliest: [String], current: String?, onChoose: @escaping (String?) -> Void) {
        (self.name, self.likeliest, self.onChoose) = (name, likeliest, onChoose)
        _selection = State(initialValue: current ?? likeliest.first)
    }

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let custom = entries.filter { $0.isOwnExercise && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
        let others = CatalogExercise.alphabetical.filter { query.isEmpty ? !likeliest.contains($0.id) : $0.matches(query) }
        NavigationStack {
            HStack(spacing: 0) {
                List(selection: $selection) {
                    if query.isEmpty {
                        Section("Likeliest") { ForEach(likeliest.compactMap { CatalogExercise.byID[$0] }, content: row) }
                    }
                    Section {
                        ForEach(custom) { CatalogRow(name: $0.name, detail: $0.details, photo: $0.photo).tag($0.id) }
                        ForEach(others, content: row)
                    } header: {
                        if query.isEmpty { Text("All exercises") }
                    }
                }
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { ids in ids.first.map(choose) }
                .frame(width: 360)
                Divider()
                if let selection {
                    ExercisePreview(id: selection).id(selection)
                } else {
                    ContentUnavailableView("Choose an exercise", systemImage: "dumbbell").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .searchable(text: $search, prompt: "Exercise, muscle or equipment")
            .navigationTitle(name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem { Button("New exercise") { onChoose(nil); dismiss() }.help("Keep it as your own, by this name") }
                ToolbarItem(placement: .confirmationAction) { Button("Choose") { selection.map(choose) }.disabled(selection == nil) }
            }
        }
        .frame(minWidth: 820, minHeight: 620)
    }

    private func row(_ exercise: CatalogExercise) -> some View {
        CatalogRow(name: exercise.label, detail: exercise.detail, imageURL: exercise.imageURL).tag(exercise.id)
    }

    private func choose(_ id: String) {
        onChoose(id)
        dismiss()
    }
}
#endif
