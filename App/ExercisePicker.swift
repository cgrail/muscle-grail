import Core
import SwiftUI

/// Searchable exercise catalog. Search text can also be added as a custom exercise.
struct ExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let onPick: (String) -> Void

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let results = query.isEmpty ? CatalogExercise.all : CatalogExercise.all.filter { $0.matches(query) }
        NavigationStack {
            List {
                if !query.isEmpty {
                    Button("Add “\(query)”", systemImage: "plus") { pick(query) }
                }
                ForEach(results) { exercise in
                    Button { pick(exercise.name) } label: { CatalogRow(exercise: exercise) }
                        .buttonStyle(.plain)
                }
            }
            .searchable(text: $search, prompt: "Exercise, muscle or equipment")
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    private func pick(_ name: String) {
        onPick(name)
        dismiss()
    }
}

private struct CatalogRow: View {
    let exercise: CatalogExercise

    var body: some View {
        HStack {
            AsyncImage(url: exercise.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.2)
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(exercise.name)
                Text(exercise.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}
