import Core
import SwiftData
import SwiftUI

struct TrainView: View {
    @State private var path: [Workout] = []

    var body: some View {
        NavigationStack(path: $path) {
            WorkoutPicker { path = [$0] }
                .navigationDestination(for: Workout.self) { WorkoutView(workout: $0) }
        }
    }
}

private struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let workout: Workout

    var body: some View {
        List {
            ForEach(workout.plan?.sortedItems ?? []) { ExerciseSection(item: $0, workout: workout) }
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
