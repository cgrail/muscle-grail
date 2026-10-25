import Core
import PhotosUI
import SwiftData
import SwiftUI

/// One exercise's catalog data: the bundled facts, and the user's own name, description, video link and photo.
struct ExerciseDetail: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [CatalogEntry]
    @Query(CatalogAction.newer) private var newer: [CatalogAction]
    @State private var pickedPhoto: PhotosPickerItem?
    private let id: String

    init(id: String) {
        self.id = id
        _entries = Query(filter: #Predicate { $0.id == id })
    }

    var body: some View {
        let entry = entries.first
        let bundled = CatalogExercise.byID[id]
        NavigationStack {
            Form {
                if !newer.isEmpty {
                    Label("Update Muscle Grail to edit exercises. A newer version changed them.", systemImage: "arrow.down.app")
                        .foregroundStyle(.secondary)
                }
                Group {
                    Section {
                        if let bundled {
                            LabeledContent("Name", value: bundled.name)
                            Text(bundled.detail).foregroundStyle(.secondary)
                        } else {
                            TextField("Name", text: Binding { entry?.name ?? "" } set: { context.editExercise(id, name: $0) })
                        }
                        TextField("Description", text: Binding { entry?.details ?? "" } set: { context.editExercise(id, details: $0) }, axis: .vertical)
                    }
                    Section("Video") {
                        TextField("Video link", text: Binding { entry?.videoURL ?? "" } set: { context.editExercise(id, videoURL: $0) })
                        if let url = URL(string: entry?.videoURL ?? ""), url.scheme?.hasPrefix("http") == true {
                            Link("Watch video", destination: url)
                        }
                    }
                    Section("Photo") {
                        ExercisePhoto(id: id, entry: entry).frame(maxHeight: 240)
                        PhotosPicker("Choose photo", selection: $pickedPhoto, matching: .images)
                        if entry?.photo != nil {
                            Button("Remove photo", role: .destructive) { context.setPhoto(id, to: nil) }
                        }
                    }
                }
                .disabled(!newer.isEmpty)
            }
            .formStyle(.grouped)
            .navigationTitle(exerciseName(id, entry: entry))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: pickedPhoto) {
                if let data = try? await pickedPhoto?.loadTransferable(type: Data.self) { context.setPhoto(id, to: data) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}

/// An exercise's photo, whole: the user's own, else the bundled one.
struct ExercisePhoto: View {
    let id: String
    let entry: CatalogEntry?

    var body: some View {
        if let image = entry?.photo.flatMap(Photo.image) {
            Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else if let url = CatalogExercise.byID[id]?.imageURL {
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
        }
    }
}
