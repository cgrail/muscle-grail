import Core
import SwiftData
import SwiftUI

struct TrainView: View {
    @State private var workout: Workout?
    @State private var plan: Plan?

    var body: some View {
        // Not NavigationStack(path:): the sidebar tabs on Mac and iPad compare paths across tabs and crash on a typed one.
        NavigationStack {
            picker
                .navigationDestination(item: $workout) { WorkoutView(plan: $0.plan, workout: $0) }
                .navigationDestination(item: $plan) { WorkoutView(plan: $0, workout: nil) }
                #if os(iOS)
                .toolbar { SettingsButton() }
                #endif
        }
    }

    /// The Mac has the room for covers; the iPhone and iPad list the plans.
    @ViewBuilder private var picker: some View {
        #if os(macOS)
        TrainOverview { workout = $0 } onStart: { plan = $0 }
        #else
        WorkoutPicker { workout = $0 } onStart: { plan = $0 }
        #endif
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
