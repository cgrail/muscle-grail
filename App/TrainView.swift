import Core
import SwiftData
import SwiftUI

/// Training: the plans to train. On the iPhone, the Training tab also edits them: Edit lists them in the same order to
/// delete, add and open to edit, and a plan opened to train has its own Edit.
struct TrainView: View {
    @State private var workout: Workout?
    @State private var plan: Plan?
    #if os(iOS)
    @State private var editing = false
    #endif

    var body: some View {
        // Not NavigationStack(path:): the sidebar tabs on Mac and iPad compare paths across tabs and crash on a typed one.
        NavigationStack {
            picker
                .navigationDestination(item: $workout) { WorkoutView(plan: $0.plan, workout: $0) }
                .navigationDestination(item: $plan) { WorkoutView(plan: $0, workout: nil) }
        }
    }

    /// The Mac has the room for covers; the iPhone and iPad list the plans.
    @ViewBuilder private var picker: some View {
        #if os(macOS)
        TrainOverview { workout = $0 } onStart: { plan = $0 }
        #else
        if editing {
            PlansView { editing = false }
        } else {
            WorkoutPicker { workout = $0 } onStart: { plan = $0 }
                .toolbar {
                    SettingsButton()
                    Button("Edit") { editing = true }
                }
        }
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
