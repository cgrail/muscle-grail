import Core
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(Workout.history) private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            List(workouts) { workout in
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.title).font(.headline)
                    Text(workout.start, format: .dateTime.weekday().day().month().hour().minute())
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(workout.exercises, id: \.id) { exercise in
                        HStack(spacing: 0) {
                            ExerciseName(exercise.id)
                            Text(verbatim: ": \(exercise.sets.map { "\($0.reps)×\($0.weightKg.formatted())" }.joined(separator: "  "))")
                        }
                    }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { context.deleteWorkout(workout) }
                }
            }
            .navigationTitle("History")
        }
    }
}
