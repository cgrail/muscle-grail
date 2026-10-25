import Core
import SwiftData
import SwiftUI

struct TrainView: View {
    @State private var workout: Workout?

    var body: some View {
        // Not NavigationStack(path:): the sidebar tabs on Mac and iPad compare paths across tabs and crash on a typed one.
        NavigationStack {
            WorkoutPicker { workout = $0 }
                .navigationDestination(item: $workout) { WorkoutView(workout: $0) }
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
                    List { ExerciseSection(item: item, workout: workout) }
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
