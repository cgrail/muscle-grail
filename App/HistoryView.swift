import Core
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.start, order: .reverse) private var workouts: [Workout]

    var body: some View {
        NavigationStack {
            List(workouts) { workout in
                let sets = (workout.sets ?? []).sorted { $0.date < $1.date }
                let exercises = sets.map(\.exercise).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.plan?.name ?? "Workout").font(.headline)
                    Text(workout.start, format: .dateTime.weekday().day().month().hour().minute())
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(exercises, id: \.self) { exercise in
                        let done = sets.filter { $0.exercise == exercise }
                        Text("\(exercise): \(done.map { "\($0.reps)×\($0.weightKg.formatted())" }.joined(separator: "  "))")
                    }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { context.delete(workout) }
                }
            }
            .navigationTitle("History")
        }
    }
}
