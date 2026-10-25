import SwiftData
import SwiftUI

public struct SyncStatusView: View {
    public init() {}

    public var body: some View {
        let sync = SyncMonitor.shared
        if let error = sync.lastError {
            Label(error, systemImage: "exclamationmark.icloud").foregroundStyle(.red).lineLimit(3)
        } else if let date = sync.lastSync {
            Label { Text("Synced \(date, style: .relative) ago") } icon: { Image(systemName: "checkmark.icloud") }
        } else {
            Label("Not synced yet", systemImage: "icloud")
        }
    }
}

/// Unfinished workouts and plans. Picking a plan starts a workout.
public struct WorkoutPicker: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.order) private var plans: [Plan]
    @Query(filter: #Predicate<Workout> { $0.end == nil }, sort: \Workout.start) private var unfinished: [Workout]
    private let onPick: (Workout) -> Void

    public init(onPick: @escaping (Workout) -> Void) {
        self.onPick = onPick
    }

    public var body: some View {
        List {
            ForEach(unfinished) { workout in
                Button("Continue \(workout.plan?.name ?? "workout")", systemImage: "play.fill") { onPick(workout) }
            }
            Section {
                ForEach(plans) { plan in
                    Button(plan.name) { onPick(context.startWorkout(plan)) }
                }
                if plans.isEmpty {
                    Text("No plans yet. Create one on your Mac.").foregroundStyle(.secondary)
                }
            } footer: {
                SyncStatusView()
            }
        }
        .navigationTitle("Train")
    }
}

/// One exercise of a running workout: adjust reps and weight, log the set, swipe a logged set to delete it.
public struct ExerciseSection: View {
    @Environment(\.modelContext) private var context
    private let item: PlanItem
    private let workout: Workout
    @State private var reps = 0
    @State private var weight = 0.0
    @State private var prefilled = false

    public init(item: PlanItem, workout: Workout) {
        self.item = item
        self.workout = workout
    }

    public var body: some View {
        let done = workout.sets(of: item.exercise)
        Section {
            Stepper("\(reps) reps", value: $reps, in: 0...200)
            Stepper("\(weight.formatted()) kg", value: $weight, in: 0...1000, step: 2.5)
            Button("Log set \(done.count + 1) of \(item.targetSets)", systemImage: "checkmark") {
                context.log(item.exercise, reps: reps, weightKg: weight, in: workout)
            }
            ForEach(done) { set in
                Text("\(set.reps) × \(set.weightKg.formatted()) kg")
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            context.delete(set)
                            try? context.save()
                        }
                    }
            }
        } header: {
            Text(item.exercise)
        }
        .onAppear {
            guard !prefilled else { return }
            prefilled = true
            (reps, weight) = suggestion(for: item, done: done, last: context.lastSets(of: item.exercise, excluding: workout))
        }
    }
}
