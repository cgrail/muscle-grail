import Core
import SwiftData
import SwiftUI

struct TrainView: View {
    @State private var workout: Workout?
    @State private var showingSettings = false

    var body: some View {
        // Not NavigationStack(path:): the sidebar tabs on Mac and iPad compare paths across tabs and crash on a typed one.
        NavigationStack {
            WorkoutPicker { workout = $0 }
                .navigationDestination(item: $workout) { WorkoutView(workout: $0) }
                #if os(iOS)
                .toolbar { Button("Settings", systemImage: "gear") { showingSettings = true } }
                .sheet(isPresented: $showingSettings) { SettingsSheet() }
                #endif
        }
    }
}

private struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let workout: Workout

    var body: some View {
        List {
            ForEach(workout.plan?.sortedItems ?? []) { item in
                NavigationLink {
                    List {
                        ExerciseSection(item: item, workout: workout)
                        ExerciseGuide(id: item.exerciseID)
                    }
                    .navigationTitle(context.exerciseName(item.exerciseID))
                } label: {
                    ExerciseRow(item: item, workout: workout)
                }
            }
        }
        .navigationTitle(workout.title)
        .toolbar {
            Button("Finish") {
                context.finish(workout)
                #if os(iOS) // the Mac has no HealthKit
                Task {
                    if let id = await Health.save(workout) { context.savedToHealth(workout, as: id) }
                }
                #endif
                dismiss()
            }
        }
    }
}

/// How to do an exercise, and a video of it, under its sets.
struct ExerciseGuide: View {
    @Query private var entries: [CatalogEntry]
    private let id: String

    init(id: String) {
        self.id = id
        _entries = Query(filter: #Predicate { $0.id == id })
    }

    var body: some View {
        let entry = entries.first
        Section("How to") {
            ForEach(instructions(id, entry: entry), id: \.self) { Text(verbatim: $0) }
            if let url = videoURL(id, entry: entry) {
                Link(destination: url) { Label("Watch video", systemImage: "play.rectangle") }
            }
        }
    }
}
