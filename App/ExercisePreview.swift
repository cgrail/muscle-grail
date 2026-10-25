#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// The selected exercise as Finder previews a file: its photo and name, its facts, then how to do it.
struct ExercisePreview: View {
    @Query private var entries: [CatalogEntry]
    private let id: String

    init(id: String) {
        self.id = id
        _entries = Query(filter: #Predicate { $0.id == id })
    }

    var body: some View {
        Form {
            Section {
                ExercisePhoto(id: id, entry: entries.first).frame(maxWidth: .infinity)
                ExerciseName(id).font(.title2.bold())
            }
            if let bundled = CatalogExercise.byID[id] {
                Section("Information") {
                    LabeledContent("Muscles", value: bundled.primaryMuscles.map(catalogTerm).joined(separator: ", "))
                    if let equipment = bundled.equipment { LabeledContent("Equipment", value: catalogTerm(equipment)) }
                }
            }
            ExerciseGuide(id: id)
        }
        .formStyle(.grouped)
    }
}
#endif
