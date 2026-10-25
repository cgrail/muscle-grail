#if os(iOS)
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
        .navigationTitle(workout.plan?.name ?? "Workout")
        .toolbar {
            Button("Finish") {
                workout.end = .now
                try? context.save()
                Task {
                    await Health.save(workout)
                    try? context.save()
                }
                dismiss()
            }
        }
    }
}
#endif
